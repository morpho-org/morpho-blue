import { hexZeroPad } from "@ethersproject/bytes";
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Wallet, constants, utils } from "ethers";
import hre from "hardhat";
import { Blue, OracleMock, ERC20Mock } from "types";

const iterations = 500;
const closePositions = false;
const nbLiquidations = 5;
expect(2 * nbLiquidations + 1 < 20, "more liquidations than signers");
const initBalance = constants.MaxUint256.div(2);

let seed = 42;

function next() {
  seed = (seed * 16807) % 2147483647;
  return seed;
}

function random() {
  return (next() - 1) / 2147483646;
}

const abiCoder = new utils.AbiCoder();

function identifier(market: Market) {
  const values = Object.values(market);
  const encodedMarket = abiCoder.encode(["address", "address", "address", "address", "uint256"], values);

  return Buffer.from(utils.keccak256(encodedMarket).slice(2), "hex");
}

interface Market {
  borrowableAsset: string;
  collateralAsset: string;
  borrowableOracle: string;
  collateralOracle: string;
  lLTV: BigNumber;
}

describe("Blue", () => {
  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let liquidator: SignerWithAddress;

  let blue: Blue;
  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let borrowableOracle: OracleMock;
  let collateralOracle: OracleMock;

  let market: Market;
  let id: Buffer;

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();
    admin = signers[2 * nbLiquidations];
    liquidator = signers[2 * nbLiquidations + 1];

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", admin);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI", 18);
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC", 18);

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", admin);

    borrowableOracle = await OracleMockFactory.deploy();
    collateralOracle = await OracleMockFactory.deploy();

    await borrowableOracle.connect(admin).setPrice(BigNumber.WAD);
    await collateralOracle.connect(admin).setPrice(BigNumber.WAD);

    const BlueFactory = await hre.ethers.getContractFactory("Blue", admin);

    blue = await BlueFactory.deploy();

    market = {
      borrowableAsset: borrowable.address,
      collateralAsset: collateral.address,
      borrowableOracle: borrowableOracle.address,
      collateralOracle: collateralOracle.address,
      lLTV: BigNumber.WAD,
    };

    id = identifier(market);

    await blue.connect(admin).createMarket(market);
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 1; i < iterations; ++i) {
      console.log(i, "/", iterations);

      const user = new Wallet(hexZeroPad(BigNumber.from(i).toHexString(), 32), hre.ethers.provider);
      await setBalance(user.address, initBalance);
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(blue.address, constants.MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(blue.address, constants.MaxUint256);

      let amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));

      let supplyOnly: boolean = random() < 2 / 3;
      if (supplyOnly) {
        if (amount > BigNumber.from(0)) {
          await blue.connect(user).supply(market, amount);
          await blue.connect(user).withdraw(market, amount.div(2));
        }
      } else {
        const totalSupply = await blue.totalSupply(id);
        const totalBorrow = await blue.totalBorrow(id);
        let liq = BigNumber.from(totalSupply).sub(BigNumber.from(totalBorrow));
        amount = BigNumber.min(amount, BigNumber.from(liq).div(2));

        if (amount > BigNumber.from(0)) {
          await blue.connect(user).supplyCollateral(market, amount);
          await blue.connect(user).borrow(market, amount.div(2));
          await blue.connect(user).repay(market, amount.div(4));
          await blue.connect(user).withdrawCollateral(market, amount.div(8));
        }
      }
    }
  });

  it("should simulate gas cost [liquidations]", async () => {
    let liquidationData = [];

    // Create accounts close to liquidation
    for (let i = 0; i < 2 * nbLiquidations; ++i) {
      const user = signers[i];
      const tranche = Math.floor(1 + i / 2);
      const lLTV = BigNumber.WAD.mul(tranche).div(nbLiquidations + 1);

      const amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));
      const borrowedAmount = amount.mul(lLTV).div(BigNumber.WAD);
      const maxSeize = closePositions ? constants.MaxUint256 : amount.div(2);

      market.lLTV = lLTV;
      // We use 2 different users to borrow from a market so that liquidations do not put the borrow storage back to 0 on that market.
      // Consequently, we should only create the market on a particular LLTV once.
      if (i % 2 == 0) {
        await blue.connect(admin).createMarket(market);
        liquidationData.push({
          lLTV: lLTV,
          borrower: user.address,
          maxSeize: maxSeize,
        });
      }

      await setBalance(user.address, initBalance);
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(blue.address, constants.MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(blue.address, constants.MaxUint256);

      await blue.connect(user).supply(market, amount);
      await blue.connect(user).supplyCollateral(market, amount);

      await blue.connect(user).borrow(market, borrowedAmount);
    }

    await borrowableOracle.connect(admin).setPrice(BigNumber.WAD.mul(1000));

    await setBalance(liquidator.address, initBalance);
    await borrowable.connect(liquidator).approve(blue.address, constants.MaxUint256);
    await borrowable.setBalance(liquidator.address, initBalance);
    for (let i = 0; i < liquidationData.length; i++) {
      let data = liquidationData[i];
      market.lLTV = data.lLTV;
      await blue.connect(liquidator).liquidate(market, data.borrower, data.maxSeize);
    }

    for (let i = 0; i < 2 * nbLiquidations; i++) {
      const user = signers[i];
      const tranche = Math.floor(1 + i / 2);
      const lLTV = BigNumber.WAD.mul(tranche).div(nbLiquidations + 1);

      market.lLTV = lLTV;
      id = identifier(market);

      let collat = await blue.collateral(id, user.address);
      expect(
        !closePositions || collat == BigNumber.from(0),
        "did not take the whole collateral when closing the position"
      );
      expect(closePositions || collat != BigNumber.from(0), "unexpectedly closed the position");
    }
  });
});
