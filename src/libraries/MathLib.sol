// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Maths utils.
library MathLib {
    uint internal constant WAD = 1e18;

    function min(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? x : y;
    }

    /// @dev Rounds towards zero.
    function wMul(uint x, uint y) internal pure returns (uint z) {
        z = (x * y) / WAD;
    }

    /// @dev Rounds towards zero.
    function wMul(int x, uint y) internal pure returns (int z) {
        z = (x * int(y)) / int(WAD);
    }

    /// @dev Rounds towards zero.
    function wDiv(uint x, uint y) internal pure returns (uint z) {
        z = (x * WAD) / y;
    }

    /// @dev Rounds towards zero.
    function wDiv(int x, uint y) internal pure returns (int z) {
        z = (x * int(WAD)) / int(y);
    }

    /// @dev Reverts if the input is negative.
    function safeToUint(int x) internal pure returns (uint z) {
        require(x >= 0);
        z = uint(x);
    }
}
