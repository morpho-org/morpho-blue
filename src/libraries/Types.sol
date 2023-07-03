// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";

library Types {
    struct MarketParams {
        address collateralToken;
        address debtToken;
        address oracle;
        address interestRateModel;
        bytes32 salt;
    }

    struct Market {
        mapping(uint256 lltv => Tranche) tranches;
        bytes32 feeRecipient;
        uint256 fee; // in basis points
        address deployer;
        address callBack;
        EnumerableSet.AddressSet wlSuppliers;
        EnumerableSet.AddressSet wlBorrowers;
    }

    struct Tranche {
        Liquidity supply;
        Liquidity debt;
        uint256 liquidationBonus;
        uint256 lastUpdateTimestamp;
        uint256 collateralAccrualIndex;
        mapping(bytes32 positionKey => Position) positions;
    }

    struct Liquidity {
        uint256 shares;
        uint256 amount;
    }

    struct Position {
        uint256 collateral;
        uint256 supplyShares;
        uint256 debtShares;
        uint256 collateralAccrualIndex;
    }

    struct OracleData {
        uint256 price;
        bool liquidationPaused;
        bool borrowPaused;
    }
}
