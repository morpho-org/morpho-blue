import { defaultAbiCoder } from "@ethersproject/abi";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, constants, utils } from "ethers";
import hre from "hardhat";
import { Blue, OracleMock, ERC20Mock, IrmMock } from "types";
import { MarketStruct } from "types/src/Blue";

const closePositions = false;
const initBalance = constants.MaxUint256.div(2);

let seed = 42;
const random = () => {
  seed = (seed * 16807) % 2147483647;

  return (seed - 1) / 2147483646;
};

const identifier = (market: MarketStruct) => {
  const encodedMarket = defaultAbiCoder.encode(
    ["address", "address", "address", "address", "address", "uint256"],
    Object.values(market),
  );

  return Buffer.from(utils.keccak256(encodedMarket).slice(2), "hex");
};

interface Market {
  id: Buffer;
  struct: MarketStruct;
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
  let irm: IrmMock;

  let market: Market;

  let nbLiquidations: number;

  const updateMarket = (market: Market, newStruct: Partial<MarketStruct>) => {
    const struct = { ...market.struct, ...newStruct };

    market = { struct, id: identifier(struct) };
  };

  beforeEach(async () => {
    const allSigners = await hre.ethers.getSigners();

    signers = allSigners.slice(0, -2);
    [admin, liquidator] = allSigners.slice(-2);

    nbLiquidations = Math.floor((signers.length - 2) / 2);

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", admin);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI", 18);
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC", 18);

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", admin);

    borrowableOracle = await OracleMockFactory.deploy();
    collateralOracle = await OracleMockFactory.deploy();

    await borrowableOracle.setPrice(BigNumber.WAD);
    await collateralOracle.setPrice(BigNumber.WAD);

    const BlueFactory = await hre.ethers.getContractFactory("Blue", admin);

    blue = await BlueFactory.deploy(admin.address);

    const IrmMockFactory = await hre.ethers.getContractFactory("IrmMock", admin);

    irm = await IrmMockFactory.deploy(blue.address);

    const struct: MarketStruct = {
      borrowableAsset: borrowable.address,
      collateralAsset: collateral.address,
      borrowableOracle: borrowableOracle.address,
      collateralOracle: collateralOracle.address,
      irm: irm.address,
      lltv: BigNumber.WAD.div(2).add(1),
    };
    market = { struct, id: identifier(struct) };

    await blue.enableLltv(market.struct.lltv);
    await blue.enableIrm(market.struct.irm);

    await blue.createMarket(market.struct);

    for (const signer of signers) {
      await borrowable.setBalance(signer.address, initBalance);
      await borrowable.connect(signer).approve(blue.address, constants.MaxUint256);
      await collateral.setBalance(signer.address, initBalance);
      await collateral.connect(signer).approve(blue.address, constants.MaxUint256);
    }

    await borrowable.setBalance(admin.address, initBalance);
    await borrowable.connect(admin).approve(blue.address, constants.MaxUint256);

    await borrowable.setBalance(liquidator.address, initBalance);
    await borrowable.connect(liquidator).approve(blue.address, constants.MaxUint256);
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 0; i < signers.length; ++i) {
      if (i % 20 == 0) console.log("[main]", Math.floor((100 * i) / signers.length), "%");

      if (random() < 1 / 2) await mine(1 + Math.floor(random() * 100), { interval: 12 });

      const user = signers[i];

      let amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));

      if (random() < 2 / 3) {
        await blue.connect(user).supply(market.struct, amount, user.address, {
          value: market.struct.borrowableAsset === constants.AddressZero ? amount : 0,
        });
        await blue.connect(user).withdraw(market.struct, amount.div(2), user.address);
      } else {
        const totalSupply = await blue.totalSupply(market.id);
        const totalBorrow = await blue.totalBorrow(market.id);
        const liquidity = BigNumber.from(totalSupply).sub(BigNumber.from(totalBorrow));

        amount = BigNumber.min(amount, BigNumber.from(liquidity).div(2));

        if (amount > BigNumber.from(0)) {
          await blue.connect(user).supplyCollateral(market.struct, amount, user.address, {
            value: market.struct.collateralAsset === constants.AddressZero ? amount : 0,
          });
          await blue.connect(user).borrow(market.struct, amount.div(2), user.address);
          await blue.connect(user).repay(market.struct, amount.div(4), user.address, {
            value: market.struct.borrowableAsset === constants.AddressZero ? amount.div(4) : 0,
          });
          await blue.connect(user).withdrawCollateral(market.struct, amount.div(8), user.address);
        }
      }
    }
  });

  it("should simulate gas cost [liquidations]", async () => {
    for (let i = 0; i < nbLiquidations; ++i) {
      if (i % 20 == 0) console.log("[liquidations]", Math.floor((100 * i) / nbLiquidations), "%");

      const user = signers[i];
      const borrower = signers[nbLiquidations + i];

      const lltv = BigNumber.WAD.mul(i + 1).div(nbLiquidations + 1);
      const amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));
      const borrowedAmount = amount.wadMulDown(lltv.sub(1));

      if (!(await blue.isLltvEnabled(lltv))) {
        await blue.enableLltv(lltv);
        await blue.enableIrm(market.struct.irm);
        await blue.createMarket({ ...market.struct, lltv });
      }

      updateMarket(market, { lltv });

      // We use 2 different users to borrow from a market so that liquidations do not put the borrow storage back to 0 on that market.
      await blue.connect(user).supply(market.struct, amount, user.address);
      await blue.connect(user).supplyCollateral(market.struct, amount, user.address);
      await blue.connect(user).borrow(market.struct, borrowedAmount, user.address);

      await blue.connect(borrower).supply(market.struct, amount, borrower.address);
      await blue.connect(borrower).supplyCollateral(market.struct, amount, borrower.address);
      await blue.connect(borrower).borrow(market.struct, borrowedAmount, borrower.address);

      await borrowableOracle.setPrice(BigNumber.WAD.mul(1000));

      const seized = closePositions ? constants.MaxUint256 : amount.div(2);

      await blue.connect(liquidator).liquidate(market.struct, borrower.address, seized, {
        value: market.struct.borrowableAsset === constants.AddressZero ? amount : 0,
      });

      const remainingCollateral = await blue.collateral(market.id, borrower.address);

      if (closePositions)
        expect(remainingCollateral.isZero(), "did not take the whole collateral when closing the position").to.be.true;
      else expect(!remainingCollateral.isZero(), "unexpectedly closed the position").to.be.true;

      await borrowableOracle.setPrice(BigNumber.WAD);
    }
  });
});
