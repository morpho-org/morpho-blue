// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @dev Inspired by morpho-utils.
library UtilsLib {
    /// @dev Returns max(x - y, 0).
    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns true iff there is exaclty one zero.
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := xor(iszero(x), iszero(y))
        }
    }
}
