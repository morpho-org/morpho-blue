// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {MarketParams} from "./IBlue.sol";

interface IIrm {
    function borrowRate(MarketParams memory marketParams) external returns (uint256);
}
