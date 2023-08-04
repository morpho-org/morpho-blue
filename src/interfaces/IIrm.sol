// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "./IBlue.sol";

interface IIrm {
    function borrowRate(Market memory market) external returns (uint256);
}
