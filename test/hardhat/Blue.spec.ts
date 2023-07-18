import { mine, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { AbiCoder, MaxUint256, Wallet, keccak256, toBeHex, toBigInt } from "ethers";
import hre from "hardhat";
import { Blue, OracleMock, ERC20Mock, IrmMock } from "types";

const iterations = 400;
const closePositions = false;
const nbLiquidations = 50;
// The liquidations gas test expects that 2*nbLiquidations + 1 is strictly less than the number of signers.
const initBalance = MaxUint256 / 2n;

let seed = 42;

function next() {
  seed = (seed * 16807) % 2147483647;
  return seed;
}

function random() {
  return (next() - 1) / 2147483646;
}

function identifier(market: Market) {
  const values = Object.values(market);
  const encodedMarket = AbiCoder.defaultAbiCoder().encode(
    ["address", "address", "address", "address", "address", "uint256"],
    values,
  );

  return Buffer.from(keccak256(encodedMarket).slice(2), "hex");
}

interface Market {
  borrowableAsset: string;
  collateralAsset: string;
  borrowableOracle: string;
  collateralOracle: string;
  irm: string;
  lltv: bigint;
}

describe("Blue", () => {
  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let liquidator: SignerWithAddress;

  let blueAddress: string;

  let blue: Blue;
  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let borrowableOracle: OracleMock;
  let collateralOracle: OracleMock;
  let irm: IrmMock;
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

    await borrowableOracle.connect(admin).setPrice(0); // Make health check always pass.
    await collateralOracle.connect(admin).setPrice(BigInt.WAD);

    const BlueFactory = await hre.ethers.getContractFactory("Blue", admin);

    blue = await BlueFactory.deploy(admin.address);
    blueAddress = await blue.getAddress();

    const IrmMockFactory = await hre.ethers.getContractFactory("IrmMock", admin);

    irm = await IrmMockFactory.deploy(blueAddress);

    market = {
      borrowableAsset: await borrowable.getAddress(),
      collateralAsset: await collateral.getAddress(),
      borrowableOracle: await borrowableOracle.getAddress(),
      collateralOracle: await collateralOracle.getAddress(),
      irm: await irm.getAddress(),
      lltv: BigInt.WAD / 2n,
    };

    id = identifier(market);

    await blue.connect(admin).enableLltv(market.lltv);
    await blue.connect(admin).enableIrm(market.irm);
    await blue.connect(admin).createMarket(market);
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 1; i < iterations; ++i) {
      if (i % 20 == 0) console.log("main:", (100 * i) / iterations, "% complete");

      await mine(Math.floor(random() * 100), { interval: 12 });

      const user = new Wallet(toBeHex(i, 32), hre.ethers.provider);
      await setBalance(user.address, initBalance);
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(blueAddress, MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(blueAddress, MaxUint256);

      let amount = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));

      const supplyOnly: boolean = random() < 2 / 3;
      if (supplyOnly) {
        if (amount > 0n) {
          await blue.connect(user).supply(market, amount);
          await blue.connect(user).withdraw(market, amount / 2n);
        }
      } else {
        const totalSupply = await blue.totalSupply(id);
        const totalBorrow = await blue.totalBorrow(id);

        amount = BigInt.min(amount, (totalSupply - totalBorrow) / 2n);

        if (amount > 0n) {
          await blue.connect(user).supplyCollateral(market, amount);
          await blue.connect(user).borrow(market, amount / 2n);
          await blue.connect(user).repay(market, amount / 4n);
          await blue.connect(user).withdrawCollateral(market, amount / 8n);
        }
      }
    }
  });

  it("should simulate gas cost [liquidations]", async () => {
    let liquidationData = [];

    // Create accounts close to liquidation
    for (let i = 0; i < 2 * nbLiquidations; ++i) {
      const user = signers[i];
      const tranche = toBigInt(Math.floor(1 + i / 2));
      market.lltv = (BigInt.WAD * tranche) / toBigInt(nbLiquidations + 1);

      const amount = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));
      const borrowedAmount = (amount * market.lltv) / BigInt.WAD;
      const maxSeize = closePositions ? MaxUint256 : amount / 2n;

      // We use 2 different users to borrow from a market so that liquidations do not put the borrow storage back to 0 on that market.
      // Consequently, we should only create the market on a particular lltv once.
      if (i % 2 == 0) {
        await blue.connect(admin).enableLltv(market.lltv);
        await blue.connect(admin).enableIrm(market.irm);
        await blue.connect(admin).createMarket(market);
        liquidationData.push({
          lltv: market.lltv,
          borrower: user.address,
          maxSeize: maxSeize,
        });
      }

      await setBalance(user.address, initBalance);
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(blueAddress, MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(blueAddress, MaxUint256);

      await blue.connect(user).supply(market, amount);
      await blue.connect(user).supplyCollateral(market, amount);

      await blue.connect(user).borrow(market, borrowedAmount);
    }

    await borrowableOracle.connect(admin).setPrice(BigInt.WAD * 1000n);

    await setBalance(liquidator.address, initBalance);
    await borrowable.connect(liquidator).approve(blueAddress, MaxUint256);
    await borrowable.setBalance(liquidator.address, initBalance);
    for (let i = 0; i < liquidationData.length; i++) {
      let data = liquidationData[i];
      market.lltv = data.lltv;
      await blue.connect(liquidator).liquidate(market, data.borrower, data.maxSeize);
    }

    for (let i = 0; i < 2 * nbLiquidations; i++) {
      const user = signers[i];
      const tranche = toBigInt(Math.floor(1 + i / 2));
      market.lltv = (BigInt.WAD * tranche) / toBigInt(nbLiquidations + 1);

      id = identifier(market);

      let collat = await blue.collateral(id, user.address);
      expect(!closePositions || collat == 0n, "did not take the whole collateral when closing the position").true;
      expect(closePositions || collat != 0n, "unexpectedly closed the position").true;
    }
  });
});
