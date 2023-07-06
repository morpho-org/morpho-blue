// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "src/Blue.sol";

interface IIRM {
    function borrowRate(Market calldata market) external returns (uint);
}
