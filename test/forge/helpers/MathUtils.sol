// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

abstract contract MathUtils {
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
