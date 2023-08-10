// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UtilsLib} from "./UtilsLib.sol";

uint256 constant WAD = 1e18;

/// @notice Fixed-point arithmetic library.
/// @dev Greatly inspired by Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol)
/// and by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
library FixedPointMathLib {
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

    /// @dev The sum of the last three terms in a four term taylor series expansion
    ///      to approximate a compound interest rate: (1 + x)^n - 1.
    function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = wMulDown(firstTerm, x * UtilsLib.zeroFloorSub(n, 1)) / 2;
        uint256 thirdTerm = wMulDown(secondTerm, x * UtilsLib.zeroFloorSub(n, 2)) / 3;

        return firstTerm + secondTerm + thirdTerm;
    }

    /// @dev (x * y) / denominator rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) { revert(0, 0) }

            // Divide x * y by the denominator.
            z := div(mul(x, y), denominator)
        }
    }

    /// @dev (x * y) / denominator rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) { revert(0, 0) }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(gt(mod(mul(x, y), denominator), 0), div(mul(x, y), denominator))
        }
    }
}
