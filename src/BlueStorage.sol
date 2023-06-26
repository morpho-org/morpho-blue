// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Types} from "src/libraries/Types.sol";

abstract contract BlueStorage {
    mapping(bytes32 key => Types.Market) internal _markets;
}
