// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface IInterestRatesManager {
    function rate(uint256 utilization, uint256 lltv) external returns (uint256);
}
