import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { AbiCoder, MaxUint256, keccak256, toBigInt } from "ethers";
import hre from "hardhat";
import { Morpho, OracleMock, ERC20Mock, IrmMock } from "types";
import { MarketParamsStruct } from "types/src/Morpho";
import { FlashBorrowerMock } from "types/src/mocks/FlashBorrowerMock";

const closePositions = false;
// Without the division it overflows.
const initBalance = MaxUint256 / 10000000000000000n;
const oraclePriceScale = 1000000000000000000000000000000000000n;

let seed = 42;
const random = () => {
  seed = (seed * 16807) % 2147483647;

  return (seed - 1) / 2147483646;
};

const identifier = (marketParams: MarketParamsStruct) => {
  const encodedMarket = AbiCoder.defaultAbiCoder().encode(
    ["address", "address", "address", "address", "uint256"],
    Object.values(marketParams),
  );

  return Buffer.from(keccak256(encodedMarket).slice(2), "hex");
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

  let marketParams: MarketParamsStruct;
  let id: Buffer;

  let nbLiquidations: number;

  const updateMarket = (newMarket: Partial<MarketParamsStruct>) => {
    marketParams = { ...marketParams, ...newMarket };
    id = identifier(marketParams);
  };

  beforeEach(async () => {
    const allSigners = await hre.ethers.getSigners();

    signers = allSigners.slice(0, -2);
    [admin, liquidator] = allSigners.slice(-2);

    nbLiquidations = Math.floor((signers.length - 2) / 2);

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", admin);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI");
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC");

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", admin);

    oracle = await OracleMockFactory.deploy();

    await oracle.setPrice(oraclePriceScale);

    const MorphoFactory = await hre.ethers.getContractFactory("Morpho", admin);

    morpho = await MorphoFactory.deploy(admin.address);

    const IrmMockFactory = await hre.ethers.getContractFactory("IrmMock", admin);

    irm = await IrmMockFactory.deploy();

    updateMarket({
      borrowableToken: await borrowable.getAddress(),
      collateralToken: await collateral.getAddress(),
      oracle: await oracle.getAddress(),
      irm: await irm.getAddress(),
      lltv: BigInt.WAD / 2n + 1n,
    });

    await morpho.enableLltv(marketParams.lltv);
    await morpho.enableIrm(marketParams.irm);
    await morpho.createMarket(marketParams);

    const morphoAddress = await morpho.getAddress();

    for (const signer of signers) {
      await borrowable.setBalance(signer.address, initBalance);
      await borrowable.connect(signer).approve(morphoAddress, MaxUint256);
      await collateral.setBalance(signer.address, initBalance);
      await collateral.connect(signer).approve(morphoAddress, MaxUint256);
    }

    await borrowable.setBalance(admin.address, initBalance);
    await borrowable.connect(admin).approve(morphoAddress, MaxUint256);

    await borrowable.setBalance(liquidator.address, initBalance);
    await borrowable.connect(liquidator).approve(morphoAddress, MaxUint256);

    const FlashBorrowerFactory = await hre.ethers.getContractFactory("FlashBorrowerMock", admin);

    flashBorrower = await FlashBorrowerFactory.deploy(morphoAddress);
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 0; i < signers.length; ++i) {
      console.log("[main]", i, "/", signers.length);

      const user = signers[i];

      let assets = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));

      await morpho.connect(user).supply(marketParams, assets, 0, user.address, "0x");
      await morpho.connect(user).withdraw(marketParams, assets / 2n, 0, user.address, user.address);
      const totalSupplyAssets = (await morpho.market(id)).totalSupplyAssets;
      const totalBorrowAssets = (await morpho.market(id)).totalBorrowAssets;
      const liquidity = totalSupplyAssets - totalBorrowAssets;

      assets = BigInt.min(assets, liquidity / 2n);

      await morpho.connect(user).supplyCollateral(marketParams, assets, user.address, "0x");
      await morpho.connect(user).borrow(marketParams, assets / 2n, 0, user.address, user.address);
      await morpho.connect(user).repay(marketParams, assets / 4n, 0, user.address, "0x");
      await morpho.connect(user).withdrawCollateral(marketParams, assets / 8n, user.address, user.address);
    }

    await hre.network.provider.send("evm_setAutomine", [true]);
  });

  it("should simulate gas cost [liquidations]", async () => {
    for (let i = 0; i < nbLiquidations; ++i) {
      if (i % 20 == 0) console.log("[liquidations]", Math.floor((100 * i) / nbLiquidations), "%");

      const user = signers[i];
      const borrower = signers[nbLiquidations + i];

      const lltv = (BigInt.WAD * toBigInt(i + 1)) / toBigInt(nbLiquidations + 1);
      const assets = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));
      const borrowedAmount = assets.wadMulDown(lltv - 1n);

      if (!(await morpho.isLltvEnabled(lltv))) {
        await morpho.enableLltv(lltv);
        await morpho.createMarket({ ...marketParams, lltv });
      }

      updateMarket({ lltv });

      // We use 2 different users to borrow from a marketParams so that liquidations do not put the borrow storage back to 0 on that marketParams.
      await morpho.connect(user).supply(marketParams, assets, 0, user.address, "0x");
      await morpho.connect(user).supplyCollateral(marketParams, assets, user.address, "0x");
      await morpho.connect(user).borrow(marketParams, borrowedAmount, 0, user.address, user.address);

      await morpho.connect(borrower).supply(marketParams, assets, 0, borrower.address, "0x");
      await morpho.connect(borrower).supplyCollateral(marketParams, assets, borrower.address, "0x");
      await morpho.connect(borrower).borrow(marketParams, borrowedAmount, 0, borrower.address, user.address);

      await oracle.setPrice(oraclePriceScale / 1000n);

      const seized = closePositions ? assets : assets / 2n;

      await morpho.connect(liquidator).liquidate(marketParams, borrower.address, seized, 0, "0x");

      const remainingCollateral = (await morpho.position(id, borrower.address)).collateral;

      if (closePositions)
        expect(remainingCollateral === 0n, "did not take the whole collateral when closing the position").to.be.true;
      else expect(remainingCollateral !== 0n, "unexpectedly closed the position").to.be.true;

      await oracle.setPrice(oraclePriceScale);
    }
  });

  it("should simuate gas cost [flashLoans]", async () => {
    const user = signers[0];
    const assets = BigInt.WAD;

    await morpho.connect(user).supply(marketParams, assets, 0, user.address, "0x");

    const borrowableAddress = await borrowable.getAddress();

    const data = AbiCoder.defaultAbiCoder().encode(["address"], [borrowableAddress]);
    await flashBorrower.flashLoan(borrowableAddress, assets / 2n, data);
  });
});
