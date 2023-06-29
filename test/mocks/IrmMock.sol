// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IInterestRatesManager} from "../../src/interfaces/IInterestRatesManager.sol";

contract IrmMock is IInterestRatesManager {
    function rate(uint256 utilization, uint256) external pure returns (uint256) {
        return utilization / 365 days;
    }
}
