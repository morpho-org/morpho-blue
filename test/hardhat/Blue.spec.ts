import { hexZeroPad } from "@ethersproject/bytes";
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Wallet, constants, utils } from "ethers";
import hre from "hardhat";
import { Blue, OracleMock, ERC20Mock } from "types";

const iterations = 500;

let seed = 42;

function next() {
  seed = (seed * 16807) % 2147483647;
  return seed;
}

function random() {
  return (next() - 1) / 2147483646;
}

interface MarketParams {
  borrowableAsset: string;
  collateralAsset: string;
  borrowableOracle: string;
  collateralOracle: string;
  lLTV: BigNumber;
}

describe("Blue", () => {
  let signers: SignerWithAddress[];

  let blue: Blue;
  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let borrowableOracle: OracleMock;
  let collateralOracle: OracleMock;
  let marketParams: MarketParams;
  let id: Buffer;

  const initBalance = constants.MaxUint256.div(2);

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", signers[0]);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI", 18);
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC", 18);

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", signers[0]);

    borrowableOracle = await OracleMockFactory.deploy();
    collateralOracle = await OracleMockFactory.deploy();

    const BlueFactory = await hre.ethers.getContractFactory("Blue", signers[0]);

    blue = await BlueFactory.deploy();

    marketParams = {
      borrowableAsset: borrowable.address,
      collateralAsset: collateral.address,
      borrowableOracle: borrowableOracle.address,
      collateralOracle: collateralOracle.address,
      lLTV: BigNumber.WAD,
    };

    const abiCoder = new utils.AbiCoder();
    const values = Object.values(marketParams);
    const encodedMarket = abiCoder.encode(["address", "address", "address", "address", "uint256"], values);

    id = Buffer.from(utils.keccak256(encodedMarket).slice(2), "hex");

    await blue.connect(signers[0]).createMarket(marketParams);
  });

  it("should simulate gas cost", async () => {
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
          await blue.connect(user).supply(marketParams, amount);
          await blue.connect(user).withdraw(marketParams, amount.div(2));
        }
      } else {
        const totalSupply = (await blue.market(id)).totalSupply;
        const totalBorrow = (await blue.market(id)).totalBorrow;
        let liq = BigNumber.from(totalSupply).sub(BigNumber.from(totalBorrow));
        amount = BigNumber.min(amount, BigNumber.from(liq).div(2));

        if (amount > BigNumber.from(0)) {
          await blue.connect(user).supplyCollateral(marketParams, amount);
          await blue.connect(user).borrow(marketParams, amount.div(2));
          await blue.connect(user).repay(marketParams, amount.div(4));
          await blue.connect(user).withdrawCollateral(marketParams, amount.div(8));
        }
      }
    }
  });
});
