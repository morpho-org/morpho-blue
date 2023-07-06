// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Id} from "src/Blue.sol";

interface IIRM {
    function borrowRate(Id id) external returns (uint);
}
