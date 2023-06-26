// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Types} from "src/libraries/Types.sol";

interface IBlueInterestModel {
    function accrue(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 totalSupply,
        uint256 totalDebt,
        uint256 timeElapsed
    ) external returns (uint256 accrual);
}
