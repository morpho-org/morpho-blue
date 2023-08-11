// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @dev Inspired by morpho-utils.
library UtilsLib {
    /// @dev Returns true if there is exactly one zero.
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := xor(iszero(x), iszero(y))
        }
    }

    /// @dev Returns the min of x and y.
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }
}
