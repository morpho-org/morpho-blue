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

    /// @dev A three term taylor series expansion to approximate a compound interest rate: (1 + x)^n - 1.
    /// With an assumption of a < 500% annual interest rate over 365 days, the error is less than 8%.
    function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = x * x * n * zeroFloorSub(n, 1) / WAD;
        uint256 thirdTerm = x * x * x * n * zeroFloorSub(n, 1) * zeroFloorSub(n, 2) / (WAD * WAD);
        // This is missing a WAD because we are only looking to get interest accrued.
        return firstTerm + secondTerm / 2 + thirdTerm / 6;
    }
}
