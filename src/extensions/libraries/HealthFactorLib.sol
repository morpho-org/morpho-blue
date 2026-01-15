// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {MathLib, WAD} from "../../libraries/MathLib.sol";
import {ORACLE_PRICE_SCALE} from "../../libraries/ConstantsLib.sol";

/// @title HealthFactorLib
/// @notice Library for calculating health factor with explicit numeric value
library HealthFactorLib {
    using MathLib for uint256;

    /* ERRORS */

    error InvalidPrice();
    error InvalidLltv();

    /* FUNCTIONS */

    /// @notice Calculate health factor for a position
    /// @dev Health Factor = (Collateral Value × Liquidation Threshold) / Borrowed Value
    /// @dev Returns value scaled by WAD (1e18)
    /// @dev Returns type(uint256).max if no debt (infinitely healthy)
    /// @param collateralAmount Amount of collateral
    /// @param collateralPrice Price of collateral from oracle
    /// @param borrowedAmount Amount borrowed (in loan token)
    /// @param lltv Loan-to-value ratio (liquidation threshold)
    /// @return healthFactor The health factor scaled by WAD
    function calculateHealthFactor(
        uint256 collateralAmount,
        uint256 collateralPrice,
        uint256 borrowedAmount,
        uint256 lltv
    ) internal pure returns (uint256 healthFactor) {
        // If no debt, position is infinitely healthy
        if (borrowedAmount == 0) {
            return type(uint256).max;
        }

        // Validate inputs
        if (collateralPrice == 0) revert InvalidPrice();
        if (lltv == 0 || lltv > WAD) revert InvalidLltv();

        // Calculate collateral value in loan token terms
        // collateralValue = collateralAmount × collateralPrice / ORACLE_PRICE_SCALE
        uint256 collateralValue = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);

        // Apply liquidation threshold (LLTV)
        // adjustedCollateralValue = collateralValue × lltv / WAD
        uint256 adjustedCollateralValue = collateralValue.wMulDown(lltv);

        // Calculate health factor
        // healthFactor = adjustedCollateralValue × WAD / borrowedAmount
        healthFactor = adjustedCollateralValue.wDivDown(borrowedAmount);

        return healthFactor;
    }

    /// @notice Calculate maximum safe borrow amount for a given collateral
    /// @param collateralAmount Amount of collateral
    /// @param collateralPrice Price of collateral from oracle
    /// @param lltv Loan-to-value ratio
    /// @return maxBorrow Maximum amount that can be borrowed
    function calculateMaxBorrow(uint256 collateralAmount, uint256 collateralPrice, uint256 lltv)
        internal
        pure
        returns (uint256 maxBorrow)
    {
        if (collateralPrice == 0) revert InvalidPrice();
        if (lltv == 0 || lltv > WAD) revert InvalidLltv();

        // maxBorrow = (collateralAmount × price / ORACLE_PRICE_SCALE) × lltv / WAD
        maxBorrow = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(lltv);
    }

    /// @notice Check if a position is healthy
    /// @param healthFactor The health factor
    /// @return True if healthy (HF >= 1.0)
    function isHealthy(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor >= WAD;
    }

    /// @notice Calculate liquidation parameters based on health factor and tier
    /// @param collateralAmount Total collateral
    /// @param borrowedAmount Total borrowed
    /// @param maxLiquidationRatio Maximum % that can be liquidated (scaled by WAD)
    /// @return maxSeizableCollateral Maximum collateral that can be seized
    /// @return maxRepayableDebt Maximum debt that can be repaid
    function calculateLiquidationLimits(uint256 collateralAmount, uint256 borrowedAmount, uint256 maxLiquidationRatio)
        internal
        pure
        returns (uint256 maxSeizableCollateral, uint256 maxRepayableDebt)
    {
        // Max debt to repay = borrowedAmount × maxLiquidationRatio
        maxRepayableDebt = borrowedAmount.wMulDown(maxLiquidationRatio);

        // Max collateral to seize = collateralAmount × maxLiquidationRatio
        maxSeizableCollateral = collateralAmount.wMulDown(maxLiquidationRatio);
    }

    /// @notice Calculate required collateral for target health factor
    /// @param borrowedAmount Amount borrowed
    /// @param collateralPrice Price of collateral
    /// @param lltv Loan-to-value ratio
    /// @param targetHealthFactor Target health factor (scaled by WAD)
    /// @return requiredCollateral Collateral needed to reach target HF
    function calculateRequiredCollateral(
        uint256 borrowedAmount,
        uint256 collateralPrice,
        uint256 lltv,
        uint256 targetHealthFactor
    ) internal pure returns (uint256 requiredCollateral) {
        if (collateralPrice == 0) revert InvalidPrice();
        if (lltv == 0 || lltv > WAD) revert InvalidLltv();
        if (borrowedAmount == 0) return 0;

        // requiredCollateralValue = (borrowedAmount × targetHF) / lltv
        uint256 requiredCollateralValue = borrowedAmount.wMulDown(targetHealthFactor).wDivUp(lltv);

        // requiredCollateral = requiredCollateralValue × ORACLE_PRICE_SCALE / price
        requiredCollateral = requiredCollateralValue.mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
    }

    /// @notice Calculate health factor improvement from repaying debt
    /// @param currentCollateral Current collateral amount
    /// @param collateralPrice Price of collateral
    /// @param currentBorrowed Current borrowed amount
    /// @param repayAmount Amount to repay
    /// @param lltv Loan-to-value ratio
    /// @return newHealthFactor Health factor after repayment
    function calculateHealthFactorAfterRepay(
        uint256 currentCollateral,
        uint256 collateralPrice,
        uint256 currentBorrowed,
        uint256 repayAmount,
        uint256 lltv
    ) internal pure returns (uint256 newHealthFactor) {
        if (currentBorrowed <= repayAmount) {
            return type(uint256).max; // Fully repaid
        }

        uint256 newBorrowed = currentBorrowed - repayAmount;
        return calculateHealthFactor(currentCollateral, collateralPrice, newBorrowed, lltv);
    }

    /// @notice Calculate health factor change from adding collateral
    /// @param currentCollateral Current collateral amount
    /// @param additionalCollateral Additional collateral to add
    /// @param collateralPrice Price of collateral
    /// @param borrowedAmount Current borrowed amount
    /// @param lltv Loan-to-value ratio
    /// @return newHealthFactor Health factor after adding collateral
    function calculateHealthFactorAfterAddCollateral(
        uint256 currentCollateral,
        uint256 additionalCollateral,
        uint256 collateralPrice,
        uint256 borrowedAmount,
        uint256 lltv
    ) internal pure returns (uint256 newHealthFactor) {
        uint256 newCollateral = currentCollateral + additionalCollateral;
        return calculateHealthFactor(newCollateral, collateralPrice, borrowedAmount, lltv);
    }
}

