// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Maths utils.
library MathLib {
    uint256 internal constant WAD = 1e18;

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    /// @dev Rounds towards zero.
    function wMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * y) / WAD;
    }

    /// @dev Rounds towards zero.
    function wDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * WAD) / y;
    }

    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? x - y : 0;
    }

    /// @dev A three term taylor series expansion to accrue interest rates.
    function taylorSeriesExpansion(uint256 rate, uint256 timeElapsed) internal pure returns (uint256) {
        uint256 firstTerm = wMul(timeElapsed, rate);
        uint256 secondTerm = wMul(firstTerm, wMul(zeroFloorSub(timeElapsed, 1), rate));
        uint256 thirdTerm = wMul(secondTerm, wMul(zeroFloorSub(timeElapsed, 2), rate));
        return WAD + firstTerm + secondTerm / 2 + thirdTerm / 6;
    }
}
