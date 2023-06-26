// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

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
        bool initialized;
    }

    struct Tranche {
        Liquidity supply;
        Liquidity debt;
        uint256 liquidationBonus;
        uint256 lastUpdateTimestamp;
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
    }

    struct OracleData {
        uint256 price;
        bool liquidationPaused;
        bool borrowPaused;
    }
}
