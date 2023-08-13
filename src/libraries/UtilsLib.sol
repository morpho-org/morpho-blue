// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title UtilsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing helpers.
/// @dev Inspired by https://github.com/morpho-org/morpho-utils.
library UtilsLib {
    /// @dev Returns true if there is exactly one zero.
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := xor(iszero(x), iszero(y))
        }
    }
}
