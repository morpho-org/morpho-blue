// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {MarketParams} from "src/Blue.sol";

interface IIrm {
    function borrowRate(MarketParams calldata marketParams) external returns (uint256);
}
