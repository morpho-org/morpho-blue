import { BigNumber, BigNumberish, Wallet, constants } from "ethers";
import hre from "hardhat";

import { hexZeroPad } from "@ethersproject/bytes";
import { mine, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { OracleMock, ERC20Mock, RateModelMock, Morpho } from "types";
import { MarketKeyStruct } from "types/src/Morpho";

const NB_TRANCHES = 64;

let seed = 42;

function next() {
  seed = (seed * 16807) % 2147483647;
  return seed;
}

function random() {
  return next() / 2147483646;
}

const liquidationLtv = (trancheId: number) => BigNumber.WAD.mul(trancheId + 1).div(NB_TRANCHES);

const wallet = (privateKey: BigNumberish) =>
  new Wallet(hexZeroPad(BigNumber.from(privateKey).toHexString(), 32), hre.ethers.provider);

describe("Morpho", () => {
  let nbSuppliers: number;
  let signers: SignerWithAddress[];

  let suppliers: SignerWithAddress[];
  let borrowers: SignerWithAddress[];

  let asset: ERC20Mock;
  let collateral: ERC20Mock;
  let oracle: OracleMock;
  let rateModel: RateModelMock;

  let marketKey: MarketKeyStruct;

  let morpho: Morpho;

  const balance = constants.MaxUint256.div(1000000);

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();

    nbSuppliers = Math.floor((signers.length - 1) / 2);

    suppliers = signers.slice(1, nbSuppliers + 1);
    borrowers = signers.slice(nbSuppliers + 1);

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", signers[0]);

    asset = await ERC20MockFactory.deploy("DAI", "DAI");
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC");

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", signers[0]);

    oracle = await OracleMockFactory.deploy();

    oracle.setPrice(BigNumber.WAD);

    const RateModelMockFactory = await hre.ethers.getContractFactory("RateModelMock", signers[0]);

    rateModel = await RateModelMockFactory.deploy();

    rateModel.setDBorrowRate("1005510910765"); // 1 / (365 * 24 * 60 * 60)^2 = +100% APR per year (in RAY)

    const Morpho = await hre.ethers.getContractFactory("Morpho", signers[0]);

    morpho = await Morpho.deploy(signers[0].address);

    morpho.setIsWhitelisted(rateModel.address, true);

    marketKey = {
      collateral: collateral.address,
      asset: asset.address,
      oracle: oracle.address,
      rateModel: rateModel.address,
    };

    for (const signer of signers) {
      await asset.setBalance(signer.address, balance);
      await collateral.setBalance(signer.address, balance);

      await asset.connect(signer).approve(morpho.address, balance);
      await collateral.connect(signer).approve(morpho.address, balance);
    }
  });

  it("multiTrancheLiquidity", async () => {
    const nbUsedTranches = 1;

    const amount = BigNumber.WAD;
    const collateralAmount = amount.div(2);

    const trancheIds = new Array(nbUsedTranches).fill(0).map((_, i) => i);
    const lLtvs = trancheIds.map((trancheId) => liquidationLtv(trancheId));

    for (let i = 1; i < nbSuppliers; ++i) {
      console.log(i);

      await mine(Math.floor(random() * 100), { interval: 12 });

      const supplier = suppliers[i];
      const borrower = borrowers[i];

      let totalCollateral = constants.Zero;
      let totalBorrowed = constants.Zero;
      for (let j = 0; j < nbUsedTranches; ++j) {
        const trancheId = trancheIds[j];
        const lLtv = lLtvs[j];

        await morpho.connect(supplier).deposit(marketKey, trancheId, amount, supplier.address);
        await morpho
          .connect(supplier)
          .withdraw(marketKey, trancheId, amount.div(2), supplier.address, supplier.address);

        const borrowedAmount = collateralAmount.wadMul(lLtv);

        await morpho.connect(borrower).depositCollateral(marketKey, collateralAmount, borrower.address);
        await morpho.connect(borrower).borrow(marketKey, trancheId, borrowedAmount, borrower.address, borrower.address); // borrowing at lLtv
        await morpho.connect(borrower).repay(marketKey, trancheId, borrowedAmount.div(2), borrower.address); // borrowing at (lLtv / 2)
        await morpho
          .connect(borrower)
          .withdrawCollateral(marketKey, collateralAmount.div(2), borrower.address, borrower.address); // borrowing at lLtv again

        totalCollateral = totalCollateral.add(collateralAmount.div(2));
        totalBorrowed = totalBorrowed.add(borrowedAmount.div(2));
      }

      await oracle.setPrice(BigNumber.WAD.percentMul(10_00));

      await morpho.liquidate(
        marketKey,
        borrower.address,
        totalBorrowed,
        totalCollateral,
        signers[0].address,
        constants.AddressZero,
        []
      );

      await oracle.setPrice(BigNumber.WAD);
    }
  });
});
