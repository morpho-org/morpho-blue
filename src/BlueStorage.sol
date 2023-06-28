// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "src/libraries/Types.sol";

contract BlueStorage {
    mapping(address => Types.Market) internal _marketMap;
    mapping(address => mapping(address => bool)) isManagedBy;
    mapping(address => uint256) internal _userNonce;
}
