// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "src/libraries/Types.sol";

interface IIrm {
    function borrowRate(Market calldata market) external returns (uint256);
}
