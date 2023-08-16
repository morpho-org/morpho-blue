import { ERC20Mock__factory, Morpho__factory, OracleMock__factory } from "../types";
import { MarketStruct } from "../types/src/Morpho";
import { constants } from "ethers";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import hre, { ethers, network } from "hardhat";

const tenderlyGasTest = async () => {
  if (network.name !== "tenderly") throw new Error("This script must be run with the tenderly network");

  const [owner, ...signers] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", owner.address);
  const MorphoFactory = await ethers.getContractFactory("Morpho");
  const _morpho = await MorphoFactory.deploy(owner.address);
  // Tenderly verify is breaking the return type of the deployed function...
  await _morpho.deployed();
  console.log("Morpho deployed to:", _morpho.address);

  const morpho = Morpho__factory.connect(_morpho.address, owner);

  await morpho.connect(owner).enableLltv(parseUnits("0.85"));
  console.log(`LLTV 85% enabled`);

  const OracleFactory = await hre.ethers.getContractFactory("OracleMock", owner);
  const oracle = await OracleFactory.deploy();
  await oracle.deployed();
  await OracleMock__factory.connect(oracle.address, owner).connect(owner).setPrice(parseUnits("1800"));
  console.log("Oracle deployed to:", oracle.address, "with price", formatUnits(await oracle.price()));

  const IrmFactory = await hre.ethers.getContractFactory("IrmMock", owner);
  const irm = await IrmFactory.deploy(morpho.address);
  await irm.deployed();
  await morpho.connect(owner).enableIrm(irm.address);
  console.log("Irm deployed to:", irm.address);

  const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", owner);
  let borrowable = await ERC20MockFactory.deploy("DAI", "DAI");
  await borrowable.deployed();
  console.log("Borrowable (DAI) deployed to:", borrowable.address);

  let collateral = await ERC20MockFactory.deploy("ETH", "ETH");
  await collateral.deployed();
  console.log("Collateral (ETH) deployed to:", collateral.address);

  const market: MarketStruct = {
    borrowableToken: borrowable.address,
    collateralToken: collateral.address,
    oracle: oracle.address,
    irm: irm.address,
    lltv: parseUnits("0.85"),
  };
  console.log("Market:\n", JSON.stringify(market, null, 2));

  await morpho.connect(owner).createMarket(market);

  console.log("Market created");

  const initBalance = parseUnits("10000");

  borrowable = ERC20Mock__factory.connect(borrowable.address, owner);
  collateral = ERC20Mock__factory.connect(collateral.address, owner);

  for (const signer of signers.slice(0, 3)) {
    await borrowable.setBalance(signer.address, initBalance);
    await borrowable.connect(signer).approve(morpho.address, constants.MaxUint256);
    await collateral.setBalance(signer.address, initBalance);
    await collateral.connect(signer).approve(morpho.address, constants.MaxUint256);
    console.log(`Balance setted for ${signer.address}`);
  }

  for (const signer of signers.slice(0, 3)) {
    const assets = parseUnits("1000");
    await morpho.connect(signer).supply(market, assets, 0, signer.address, [], { gasLimit: "1000000" });
    await morpho
      .connect(signer)
      .withdraw(market, assets.div(2), 0, signer.address, signer.address, { gasLimit: "1000000" });

    await morpho.connect(signer).supplyCollateral(market, assets, signer.address, [], { gasLimit: "1000000" });
    await morpho
      .connect(signer)
      .borrow(market, assets.div(2), 0, signer.address, signer.address, { gasLimit: "1000000" });
    await morpho.connect(signer).repay(market, assets.div(4), 0, signer.address, [], { gasLimit: "1000000" });
    await morpho
      .connect(signer)
      .withdrawCollateral(market, assets.div(8), signer.address, signer.address, { gasLimit: "1000000" });
    console.log("Done for user n°", signers.slice(0, 3).indexOf(signer) + 1);
  }
};

tenderlyGasTest()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
