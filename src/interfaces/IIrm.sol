// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "./IBlue.sol";

interface IIrm {
    function borrowRate(Market calldata market) external view returns (uint256);
}
