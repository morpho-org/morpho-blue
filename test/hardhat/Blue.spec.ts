import { defaultAbiCoder } from "@ethersproject/abi";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, constants, utils } from "ethers";
import hre from "hardhat";
import { Blue, OracleMock, ERC20Mock, IrmMock } from "types";
import { MarketStruct } from "types/src/Blue";
import { FlashBorrowerMock } from "types/src/mocks/FlashBorrowerMock";

const closePositions = false;
const initBalance = constants.MaxUint256.div(2);

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

describe("Blue", () => {
  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let liquidator: SignerWithAddress;

  let blue: Blue;
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

    await oracle.setPrice(BigNumber.WAD);

    const BlueFactory = await hre.ethers.getContractFactory("Blue", admin);

    blue = await BlueFactory.deploy(admin.address);

    const IrmMockFactory = await hre.ethers.getContractFactory("IrmMock", admin);

    irm = await IrmMockFactory.deploy(blue.address);

    updateMarket({
      borrowableAsset: borrowable.address,
      collateralAsset: collateral.address,
      oracle: oracle.address,
      irm: irm.address,
      lltv: BigNumber.WAD.div(2).add(1),
    });

    await blue.enableLltv(market.lltv);
    await blue.enableIrm(market.irm);
    await blue.createMarket(market);

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

    const FlashBorrowerFactory = await hre.ethers.getContractFactory("FlashBorrowerMock", admin);

    flashBorrower = await FlashBorrowerFactory.deploy(blue.address);
  });

  it("should simulate gas cost [main]", async () => {
    await hre.network.provider.send("evm_setAutomine", [false]);
    await hre.network.provider.send("evm_setIntervalMining", [0]);

    for (let i = 0; i < signers.length; ++i) {
      if (i % 20 == 0) console.log("[main]", Math.floor((100 * i) / signers.length), "%");

      if (random() < 1 / 2) await mine(1 + Math.floor(random() * 100), { interval: 12 });

      const user = signers[i];

      let amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));

      if (random() < 2 / 3) {
        Promise.all([
          blue.connect(user).supply(market, amount, 0, user.address, []),
          blue.connect(user).withdraw(market, amount.div(2), 0, user.address, user.address),
        ]);
      } else {
        const totalSupply = await blue.totalSupply(id);
        const totalBorrow = await blue.totalBorrow(id);
        const liquidity = BigNumber.from(totalSupply).sub(BigNumber.from(totalBorrow));

        amount = BigNumber.min(amount, BigNumber.from(liquidity).div(2));

        if (amount > BigNumber.from(0)) {
          Promise.all([
            blue.connect(user).supplyCollateral(market, amount, user.address, []),
            blue.connect(user).borrow(market, amount.div(2), 0, user.address, user.address),
            blue.connect(user).repay(market, amount.div(4), 0, user.address, []),
            blue.connect(user).withdrawCollateral(market, amount.div(8), user.address, user.address),
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
      const amount = BigNumber.WAD.mul(1 + Math.floor(random() * 100));
      const borrowedAmount = amount.wadMulDown(lltv.sub(1));

      if (!(await blue.isLltvEnabled(lltv))) {
        await blue.enableLltv(lltv);
        await blue.enableIrm(market.irm);
        await blue.createMarket({ ...market, lltv });
      }

      updateMarket({ lltv });

      // We use 2 different users to borrow from a market so that liquidations do not put the borrow storage back to 0 on that market.
      await blue.connect(user).supply(market, amount, 0, user.address, "0x");
      await blue.connect(user).supplyCollateral(market, amount, user.address, "0x");
      await blue.connect(user).borrow(market, borrowedAmount, 0, user.address, user.address);

      await blue.connect(borrower).supply(market, amount, 0, borrower.address, "0x");
      await blue.connect(borrower).supplyCollateral(market, amount, borrower.address, "0x");
      await blue.connect(borrower).borrow(market, borrowedAmount, 0, borrower.address, user.address);

      await oracle.setPrice(BigNumber.WAD.div(10));

      const seized = closePositions ? constants.MaxUint256 : amount.div(2);

      await blue.connect(liquidator).liquidate(market, borrower.address, seized, "0x");

      const remainingCollateral = await blue.collateral(id, borrower.address);

      if (closePositions)
        expect(remainingCollateral.isZero(), "did not take the whole collateral when closing the position").to.be.true;
      else expect(!remainingCollateral.isZero(), "unexpectedly closed the position").to.be.true;

      await oracle.setPrice(BigNumber.WAD);
    }
  });

  it("should simuate gas cost [flashLoans]", async () => {
    const user = signers[0];
    const amount = BigNumber.WAD;

    await blue.connect(user).supply(market, amount, 0, user.address, "0x");

    const data = defaultAbiCoder.encode(["address"], [borrowable.address]);
    await flashBorrower.flashLoan(borrowable.address, amount.div(2), data);
  });
});
