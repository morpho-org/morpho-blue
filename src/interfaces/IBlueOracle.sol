// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface IBlueOracle {
    struct BlueOracleResult {
        uint256 priceMantissa;
        int256 priceExponent;
        bool disableBorrows;
        bool disableLiquidations;
    }

    function query() external returns (BlueOracleResult memory);
}
