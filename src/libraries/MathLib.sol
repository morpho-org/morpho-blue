// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;

/// @title MathLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to manage fixed-point arithmetic.
/// @dev Inspired by https://github.com/morpho-org/morpho-utils.
library MathLib {
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;

    /// @dev (x * y) / WAD rounded down.
    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    /// @dev (x * y) / WAD rounded up.
    function wMulUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD);
    }

    /// @dev (x * WAD) / y rounded down.
    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    /// @dev (x * WAD) / y rounded up.
    function wDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    /// @dev (x * y) / denominator rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        // Overflow if
        //     x * y > type(uint256).max
        // <=> y > 0 and x > type(uint256).max / y
        assembly {
            if or(mul(y, gt(x, div(MAX_UINT256, y))), iszero(denominator)) { revert(0, 0) }

            z := div(mul(x, y), denominator)
        }
    }

    /// @dev (x * y) / denominator rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        // Underflow if denominator == 0.
        // Overflow if
        //     x * y + denominator - 1 > type(uint256).max
        // <=> x * y > type(uint256).max - denominator - 1
        // <=> y > 0 and x > (type(uint256).max - denominator - 1) / y
        assembly {
            if or(mul(y, gt(x, div(sub(MAX_UINT256, sub(denominator, 1)), y))), iszero(denominator)) { revert(0, 0) }

            z := div(add(mul(x, y), sub(denominator, 1)), denominator)
        }
    }

    /// @dev The sum of the last three terms in a four term taylor series expansion
    ///      to approximate a continuous compound interest rate: e^(nx) - 1.
    function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = wMulDown(firstTerm, firstTerm) / 2;
        uint256 thirdTerm = wMulDown(secondTerm, firstTerm) / 3;

        return firstTerm + secondTerm + thirdTerm;
    }
}
