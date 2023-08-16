import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-network-helpers";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";
import * as dotenv from "dotenv";
import "ethers-maths";
import "hardhat-gas-reporter";
import "hardhat-tracer";
import { HardhatUserConfig } from "hardhat/config";
import "solidity-coverage";
import * as tdly from "@tenderly/hardhat-tenderly";
tdly.setup({
  automaticVerifications: true
});

dotenv.config();

let config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1,
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      accounts: {
        count: 252,
      },
      mining: {
        mempool: {
          order: "fifo",
        },
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.21",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
          evmVersion: "paris",
        },
      },
    ],
  },
  mocha: {
    timeout: 3000000,
  },
  typechain: {
    target: "ethers-v5",
    outDir: "types/",
    externalArtifacts: ["deps/**/*.json"],
  },
  gasReporter: {

    excludeContracts: ["src/mocks/"],
  },
  tracer: {
    defaultVerbosity: 1,
    gasCost: true,
  }
};

const tenderlyForkUrl = process.env.TENDERLY_FORK_URL;
if (tenderlyForkUrl) {
  console.log("Tenderly fork url detected, enabling tenderly network")
  config = {
    ...config,
    networks: {
      ...config.networks,
      tenderly: {
        url: tenderlyForkUrl,
      }
    },
    tenderly: {
      username: "morpho-labs", // tenderly username (or organization name)
      project: "blue", // project name
      privateVerification: true // if true, contracts will be verified privately, if false, contracts will be verified publicly
    }
  }
}

export default config;
