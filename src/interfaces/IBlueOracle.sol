// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Types} from "src/libraries/Types.sol";

interface IBlueOracle {
    function getMarketData(address collateral, address debt) external view returns (Types.OracleData memory);
}
