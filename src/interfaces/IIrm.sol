// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "src/libraries/MarketLib.sol";

interface IIrm {
    function borrowRate(Market calldata market) external view returns (uint256);
}
