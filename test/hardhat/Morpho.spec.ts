import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { setNextBlockTimestamp } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";
import { expect } from "chai";
import { AbiCoder, MaxUint256, ZeroAddress, keccak256, toBigInt } from "ethers";
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

const logProgress = (name: string, i: number, max: number) => {
  if (i % 10 == 0) console.log("[" + name + "]", Math.floor((100 * i) / max), "%");
};

const randomForwardTimestamp = async () => {
  const block = await hre.ethers.provider.getBlock("latest");
  const elapsed = random() < 1 / 2 ? 0 : (1 + Math.floor(random() * 100)) * 12; // 50% of the time, don't go forward in time.

  await setNextBlockTimestamp(block!.timestamp + elapsed);
};

describe("Morpho", () => {
  let admin: SignerWithAddress;
  let liquidator: SignerWithAddress;
  let suppliers: SignerWithAddress[];
  let borrowers: SignerWithAddress[];

  let morpho: Morpho;
  let loanToken: ERC20Mock;
  let collateralToken: ERC20Mock;
  let oracle: OracleMock;
  let irm: IrmMock;
  let flashBorrower: FlashBorrowerMock;

  let marketParams: MarketParamsStruct;
  let id: Buffer;

  const updateMarket = (newMarket: Partial<MarketParamsStruct>) => {
    marketParams = { ...marketParams, ...newMarket };
    id = identifier(marketParams);
  };

  beforeEach(async () => {
    const allSigners = await hre.ethers.getSigners();

    const users = allSigners.slice(0, -2);

    [admin, liquidator] = allSigners.slice(-2);
    suppliers = users.slice(0, users.length / 2);
    borrowers = users.slice(users.length / 2);

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", admin);

    loanToken = await ERC20MockFactory.deploy();
    collateralToken = await ERC20MockFactory.deploy();

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", admin);

    oracle = await OracleMockFactory.deploy();

    await oracle.setPrice(oraclePriceScale);

    const MorphoFactory = await hre.ethers.getContractFactory("Morpho", admin);

    morpho = await MorphoFactory.deploy(admin.address);

    const IrmMockFactory = await hre.ethers.getContractFactory("IrmMock", admin);

    irm = await IrmMockFactory.deploy();

    updateMarket({
      loanToken: await loanToken.getAddress(),
      collateralToken: await collateralToken.getAddress(),
      oracle: await oracle.getAddress(),
      irm: await irm.getAddress(),
      lltv: BigInt.WAD / 2n + 1n,
    });

    await morpho.enableLltv(marketParams.lltv);
    await morpho.enableIrm(marketParams.irm);
    await morpho.createMarket(marketParams);

    const morphoAddress = await morpho.getAddress();

    for (const user of users) {
      await loanToken.setBalance(user.address, initBalance);
      await loanToken.connect(user).approve(morphoAddress, MaxUint256);
      await collateralToken.setBalance(user.address, initBalance);
      await collateralToken.connect(user).approve(morphoAddress, MaxUint256);
    }

    await loanToken.setBalance(admin.address, initBalance);
    await loanToken.connect(admin).approve(morphoAddress, MaxUint256);

    await loanToken.setBalance(liquidator.address, initBalance);
    await loanToken.connect(liquidator).approve(morphoAddress, MaxUint256);

    const FlashBorrowerFactory = await hre.ethers.getContractFactory("FlashBorrowerMock", admin);

    flashBorrower = await FlashBorrowerFactory.deploy(morphoAddress);
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 0; i < suppliers.length; ++i) {
      logProgress("main", i, suppliers.length);

      const supplier = suppliers[i];

      let assets = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));

      await randomForwardTimestamp();

      await morpho.connect(supplier).supply(marketParams, assets, 0, supplier.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(supplier).withdraw(marketParams, assets / 2n, 0, supplier.address, supplier.address);

      const borrower = borrowers[i];

      const market = await morpho.market(id);
      const liquidity = market.totalSupplyAssets - market.totalBorrowAssets;

      assets = assets.min(liquidity / 2n);

      await randomForwardTimestamp();

      await morpho.connect(borrower).supplyCollateral(marketParams, assets, borrower.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(borrower).borrow(marketParams, assets / 2n, 0, borrower.address, borrower.address);

      await randomForwardTimestamp();

      await morpho.connect(borrower).repay(marketParams, assets / 4n, 0, borrower.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(borrower).withdrawCollateral(marketParams, assets / 8n, borrower.address, borrower.address);
    }
  });

  it("should simulate gas cost [idle]", async () => {
    updateMarket({
      loanToken: await loanToken.getAddress(),
      collateralToken: ZeroAddress,
      oracle: ZeroAddress,
      irm: ZeroAddress,
      lltv: 0,
    });

    await morpho.enableLltv(0);
    await morpho.enableIrm(ZeroAddress);
    await morpho.createMarket(marketParams);

    for (let i = 0; i < suppliers.length; ++i) {
      logProgress("idle", i, suppliers.length);

      const supplier = suppliers[i];

      let assets = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));

      await randomForwardTimestamp();

      await morpho.connect(supplier).supply(marketParams, assets, 0, supplier.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(supplier).withdraw(marketParams, assets / 2n, 0, supplier.address, supplier.address);
    }
  });

  it("should simulate gas cost [liquidations]", async () => {
    for (let i = 0; i < suppliers.length; ++i) {
      logProgress("liquidations", i, suppliers.length);

      const user = suppliers[i];
      const borrower = borrowers[i];

      const lltv = (BigInt.WAD * toBigInt(i + 1)) / toBigInt(suppliers.length + 1);
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
    const user = borrowers[0];
    const assets = BigInt.WAD;

    await morpho.connect(user).supply(marketParams, assets, 0, user.address, "0x");

    const loanAddress = await loanToken.getAddress();

    const data = AbiCoder.defaultAbiCoder().encode(["address"], [loanAddress]);
    await flashBorrower.flashLoan(loanAddress, assets / 2n, data);
  });
});
