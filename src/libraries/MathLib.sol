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

    /// @dev A taylor series expansion to approximate a compound interest rate: (1 + x)^n - 1.
    /// With an assumption of a < 500% annual interest rate over 365 days, the error is less than 8% with three terms.
    function wTaylorCompounded(uint256 x, uint256 n, uint256 numTerms) internal pure returns (uint256) {
        if (numTerms == 0) {
            return 0;
        }
        uint256 term = x * n;
        uint256 sum = term;
        if (numTerms == 1) {
            return sum;
        }
        for (uint256 i = 2; i <= numTerms; i++) {
            term = (term * x * zeroFloorSub(n, i - 1)) / (WAD * i);
            sum += term;
        }
        return sum;
    }
}
