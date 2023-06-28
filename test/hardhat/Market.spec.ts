import { BigNumber, constants } from "ethers";
import hre from "hardhat";

import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { Market, OracleMock, ERC20Mock, LiquidatorMock } from "types";

function assert(condition: boolean, message: string) {
  if (!condition) {
    throw message || "Assertion failed";
  }
}

let seed = 42;

function next() {
  seed = seed * 16807 % 2147483647;
  return seed;
}

function random() {
  return (next() - 1) / 2147483646;
}

let nbLiquidations = 5;
let nativeBatching = false;
let closePositions = false;

assert(2 * nbLiquidations + 1 < 20, "more liquidations than signers");

describe("Market", () => {
  let signers: SignerWithAddress[];

  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let borrowableOracle: OracleMock;
  let collateralOracle: OracleMock;
  let market: Market;
  let liquidatorContract: LiquidatorMock;
  let admin: SignerWithAddress;
  let liquidator: SignerWithAddress;

  const initBalance = constants.MaxUint256.div(2);

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();
    admin = signers[2 * nbLiquidations];
    liquidator = signers[2 * nbLiquidations + 1];

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", admin);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI", 18);
    collateral = await ERC20MockFactory.deploy("USDC", "USDC", 18);

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", admin);

    borrowableOracle = await OracleMockFactory.deploy();
    collateralOracle = await OracleMockFactory.deploy();

    await borrowableOracle.connect(admin).setPrice(BigNumber.WAD);
    await collateralOracle.connect(admin).setPrice(BigNumber.WAD);

    const MarketFactory = await hre.ethers.getContractFactory("Market", admin);

    market = await MarketFactory.deploy(
      borrowable.address,
      collateral.address,
      borrowableOracle.address,
      collateralOracle.address
    );

    const LiquidatorMockFactory = await hre.ethers.getContractFactory("LiquidatorMock", admin);

    liquidatorContract = await LiquidatorMockFactory.deploy();
  });

  it("should simulate gas cost", async () => {
    const n = (await market.getN()).toNumber();
    assert(2 * nbLiquidations <= n, "more liquidations than buckets");
    let liquidationData = []

    // Create accounts close to liquidation
    for (let i = 0; i < 2 * nbLiquidations; ++i) {
      const user = signers[i];
      const bucket = Math.floor(i / 2);
      await setBalance(user.address, initBalance);
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(market.address, constants.MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(market.address, constants.MaxUint256);

      let amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));

      await market.connect(user).modifyDeposit(amount, bucket);
      await market.connect(user).modifyCollateral(amount, bucket);

      let lltv = await market.bucketToLLTV(bucket);
      let borrowedAmount = amount.mul(lltv).div(BigNumber.WAD);
      await market.connect(user).modifyBorrow(borrowedAmount, bucket);

      let maxCollat = closePositions ? constants.MaxUint256 : amount.div(2);

      if (i % 2 == 0) {
        liquidationData.push({ bucket: bucket, borrower: user.address, maxCollat: maxCollat });
      }
    }

    await borrowableOracle.connect(admin).setPrice(BigNumber.WAD.mul(1000));

    await setBalance(liquidator.address, initBalance);
    await borrowable.setBalance(liquidatorContract.address, initBalance);
    await liquidatorContract.connect(liquidator).approveBorrowable(market.address);
    if (nativeBatching) {
      await liquidatorContract.connect(liquidator).nativeBatchLiquidate(market.address, liquidationData);
    } else {
      await liquidatorContract.connect(liquidator).manualBatchLiquidate(market.address, liquidationData);
    }

    for (let i = 0; i < 2 * nbLiquidations; i++) {
      const user = signers[i];
      const bucket = Math.floor(i / 2);
      let collat = await market.collateral(user.address, bucket);
      assert(closePositions || collat != BigNumber.from(0), "did not take the whole collateral when closing the position");
    }
  });
});
