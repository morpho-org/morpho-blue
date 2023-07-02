// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Maths utils.
library MathLib {
    uint internal constant WAD = 1e18;

    /// @dev Rounds towards zero.
    function wMul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / WAD;
    }

    /// @dev Rounds towards zero.
    function wDiv(uint x, uint y) internal pure returns (uint z) {
        z = (x * WAD) / y;
    }
}
