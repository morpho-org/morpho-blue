import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-network-helpers";
import "@nomicfoundation/hardhat-ethers";
import "@typechain/hardhat";
import * as dotenv from "dotenv";
import "ethers-maths";
import "hardhat-gas-reporter";
import "hardhat-tracer";
import { HardhatUserConfig } from "hardhat/config";
import "solidity-coverage";

dotenv.config();

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1,
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      accounts: {
        count: 102,
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
    ],
  },
  mocha: {
    timeout: 3000000,
  },
  typechain: {
    target: "ethers-v6",
    outDir: "types/",
    externalArtifacts: ["deps/**/*.json"],
  },
  tracer: {
    defaultVerbosity: 1,
    gasCost: true,
  },
};

export default config;
