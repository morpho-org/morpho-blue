import { defaultAbiCoder } from "@ethersproject/abi";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, constants, utils } from "ethers";
import hre from "hardhat";
import { Morpho, OracleMock, ERC20Mock, IrmMock } from "types";
import { MarketStruct } from "types/src/Morpho";
import { FlashBorrowerMock } from "types/src/mocks/FlashBorrowerMock";

const closePositions = false;
const initBalance = constants.MaxUint256.div(2);
const oraclePriceScale = BigNumber.from("1000000000000000000000000000000000000");

let seed = 42;
const random = () => {
  seed = (seed * 16807) % 2147483647;

  return (seed - 1) / 2147483646;
};

const identifier = (market: MarketStruct) => {
  const encodedMarket = defaultAbiCoder.encode(
    ["address", "address", "address", "address", "uint256"],
    Object.values(market),
  );

  return Buffer.from(utils.keccak256(encodedMarket).slice(2), "hex");
};

describe("Morpho", () => {
  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let liquidator: SignerWithAddress;

  let morpho: Morpho;
  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let oracle: OracleMock;
  let irm: IrmMock;
  let flashBorrower: FlashBorrowerMock;

  let market: MarketStruct;
  let id: Buffer;

  let nbLiquidations: number;

  const updateMarket = (newMarket: Partial<MarketStruct>) => {
    market = { ...market, ...newMarket };
    id = identifier(market);
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

    oracle = await OracleMockFactory.deploy();

    await oracle.setPrice(oraclePriceScale);

    const MorphoFactory = await hre.ethers.getContractFactory("Morpho", admin);

    morpho = await MorphoFactory.deploy(admin.address);

    const IrmMockFactory = await hre.ethers.getContractFactory("IrmMock", admin);

    irm = await IrmMockFactory.deploy(morpho.address);

    updateMarket({
      borrowableToken: borrowable.address,
      collateralToken: collateral.address,
      oracle: oracle.address,
      irm: irm.address,
      lltv: BigNumber.WAD.div(2).add(1),
    });

    await morpho.enableLltv(market.lltv);
    await morpho.enableIrm(market.irm);
    await morpho.createMarket(market);

    for (const signer of signers) {
      await borrowable.setBalance(signer.address, initBalance);
      await borrowable.connect(signer).approve(morpho.address, constants.MaxUint256);
      await collateral.setBalance(signer.address, initBalance);
      await collateral.connect(signer).approve(morpho.address, constants.MaxUint256);
    }

    await borrowable.setBalance(admin.address, initBalance);
    await borrowable.connect(admin).approve(morpho.address, constants.MaxUint256);

    await borrowable.setBalance(liquidator.address, initBalance);
    await borrowable.connect(liquidator).approve(morpho.address, constants.MaxUint256);

    const FlashBorrowerFactory = await hre.ethers.getContractFactory("FlashBorrowerMock", admin);

    flashBorrower = await FlashBorrowerFactory.deploy(morpho.address);
  });

  it("should simulate gas cost [main]", async () => {
    await hre.network.provider.send("evm_setAutomine", [false]);
    await hre.network.provider.send("evm_setIntervalMining", [0]);

    for (let i = 0; i < signers.length; ++i) {
      if (i % 20 == 0) console.log("[main]", Math.floor((100 * i) / signers.length), "%");

      if (random() < 1 / 2) await mine(1 + Math.floor(random() * 100), { interval: 12 });

      const user = signers[i];

      let assets = BigNumber.WAD.mul(1 + Math.floor(random() * 100));

      if (random() < 2 / 3) {
        Promise.all([
          morpho.connect(user).supply(market, assets, 0, user.address, []),
          morpho.connect(user).withdraw(market, assets.div(2), 0, user.address, user.address),
        ]);
      } else {
        const totalSupply = await morpho.totalSupply(id);
        const totalBorrow = await morpho.totalBorrow(id);
        const liquidity = BigNumber.from(totalSupply).sub(BigNumber.from(totalBorrow));

        assets = BigNumber.min(assets, BigNumber.from(liquidity).div(2));

        if (assets > BigNumber.from(0)) {
          Promise.all([
            morpho.connect(user).supplyCollateral(market, assets, user.address, []),
            morpho.connect(user).borrow(market, assets.div(2), 0, user.address, user.address),
            morpho.connect(user).repay(market, assets.div(4), 0, user.address, []),
            morpho.connect(user).withdrawCollateral(market, assets.div(8), user.address, user.address),
          ]);
        }
      }
    }

    await hre.network.provider.send("evm_setAutomine", [true]);
  });

  it("should simulate gas cost [liquidations]", async () => {
    for (let i = 0; i < nbLiquidations; ++i) {
      if (i % 20 == 0) console.log("[liquidations]", Math.floor((100 * i) / nbLiquidations), "%");

      const user = signers[i];
      const borrower = signers[nbLiquidations + i];

      const lltv = BigNumber.WAD.mul(i + 1).div(nbLiquidations + 1);
      const assets = BigNumber.WAD.mul(1 + Math.floor(random() * 100));
      const borrowedAmount = assets.wadMulDown(lltv.sub(1));

      if (!(await morpho.isLltvEnabled(lltv))) {
        await morpho.enableLltv(lltv);
        await morpho.enableIrm(market.irm);
        await morpho.createMarket({ ...market, lltv });
      }

      updateMarket({ lltv });

      // We use 2 different users to borrow from a market so that liquidations do not put the borrow storage back to 0 on that market.
      await morpho.connect(user).supply(market, assets, 0, user.address, "0x");
      await morpho.connect(user).supplyCollateral(market, assets, user.address, "0x");
      await morpho.connect(user).borrow(market, borrowedAmount, 0, user.address, user.address);

      await morpho.connect(borrower).supply(market, assets, 0, borrower.address, "0x");
      await morpho.connect(borrower).supplyCollateral(market, assets, borrower.address, "0x");
      await morpho.connect(borrower).borrow(market, borrowedAmount, 0, borrower.address, user.address);

      await oracle.setPrice(oraclePriceScale.div(100));

      const seized = closePositions ? assets : assets.div(2);

      await morpho.connect(liquidator).liquidate(market, borrower.address, seized, "0x");

      const remainingCollateral = await morpho.collateral(id, borrower.address);

      if (closePositions)
        expect(remainingCollateral.isZero(), "did not take the whole collateral when closing the position").to.be.true;
      else expect(!remainingCollateral.isZero(), "unexpectedly closed the position").to.be.true;

      await oracle.setPrice(oraclePriceScale);
    }
  });

  it("should simuate gas cost [flashLoans]", async () => {
    const user = signers[0];
    const assets = BigNumber.WAD;

    await morpho.connect(user).supply(market, assets, 0, user.address, "0x");

    const data = defaultAbiCoder.encode(["address"], [borrowable.address]);
    await flashBorrower.flashLoan(borrowable.address, assets.div(2), data);
  });
});
