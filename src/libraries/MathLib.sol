// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;

/// @title MathLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to manage fixed-point arithmetic.
library MathLib {
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
    function mulDivDown(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        return (x * y) / denominator;
    }

    /// @dev (x * y) / denominator rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        return (x * y + (denominator - 1)) / denominator;
    }

    /// @dev The sum of the last three terms in a four term taylor series expansion
    ///      to approximate a continuous compound interest rate: e^(nx) - 1.
    function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);

        return firstTerm + secondTerm + thirdTerm;
    }
}
