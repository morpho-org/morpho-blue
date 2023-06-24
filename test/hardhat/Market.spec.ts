import { BigNumber, Wallet, constants } from "ethers";
import hre from "hardhat";

import { hexZeroPad } from "@ethersproject/bytes";
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { Market, OracleMock, ERC20Mock } from "types";

const iterations = 500;

let seed = 42;

function next() {
  seed = seed * 16807 % 2147483647;
  return seed;
}

function random() {
  return (next() - 1) / 2147483646;
}

describe("Market", () => {
  let signers: SignerWithAddress[];

  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let borrowableOracle: OracleMock;
  let collateralOracle: OracleMock;
  let market: Market;

  const initBalance = constants.MaxUint256.div(2);

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", signers[0]);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI", 18);
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC", 18);

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", signers[0]);

    borrowableOracle = await OracleMockFactory.deploy();
    collateralOracle = await OracleMockFactory.deploy();

    const MarketFactory = await hre.ethers.getContractFactory("Market", signers[0]);

    market = await MarketFactory.deploy(
      borrowable.address,
      collateral.address,
      borrowableOracle.address,
      collateralOracle.address
    );
  });

  it("should simulate gas cost", async () => {
    const n = (await market.getN()).toNumber();

    for (let i = 1; i < iterations; ++i) {
      console.log(i, "/", iterations);

      const user = new Wallet(hexZeroPad(BigNumber.from(i).toHexString(), 32), hre.ethers.provider);
      await setBalance(user.address, initBalance);
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(market.address, constants.MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(market.address, constants.MaxUint256);

      let amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));
      const bucket = Math.floor(random() * n);

      let supplyOnly: boolean = random() < 2 / 3;
      if (supplyOnly) {
        await market.connect(user).modifyDeposit(amount, bucket);
        await market.connect(user).modifyDeposit(amount.div(2).mul(-1), bucket);
      } else {
        const totalSupply = await market.totalSupply(bucket);
        const totalBorrow = await market.totalBorrow(bucket);
        let liq = BigNumber.from(totalSupply).sub(BigNumber.from(totalBorrow));
        amount = BigNumber.min(amount, BigNumber.from(liq).div(2));

        await market.connect(user).modifyCollateral(amount);
        await market.connect(user).modifyBorrow(amount.div(2), bucket);
        await market.connect(user).modifyBorrow(amount.div(4).mul(-1), bucket);
        await market.connect(user).modifyCollateral(amount.div(8).mul(-1));
      }
    }
  });
});
