// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {MathLib, WAD} from "../../libraries/MathLib.sol";
import {ORACLE_PRICE_SCALE} from "../../libraries/ConstantsLib.sol";

/// @title HealthFactorLib
/// @notice Health factor and liquidation limit calculations
library HealthFactorLib {
    using MathLib for uint256;

    error InvalidPrice();
    error InvalidLltv();

    /// @notice Calculate health factor: (collateral * price * lltv) / borrowed
    /// @return healthFactor Scaled by WAD; >= WAD means healthy
    function calculateHealthFactor(
        uint256 collateralAmount,
        uint256 collateralPrice,
        uint256 borrowedAmount,
        uint256 lltv
    ) internal pure returns (uint256 healthFactor) {
        if (borrowedAmount == 0) return type(uint256).max;
        if (collateralPrice == 0) revert InvalidPrice();
        if (lltv == 0 || lltv > WAD) revert InvalidLltv();

        uint256 collateralValue = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        uint256 adjustedValue = collateralValue.wMulDown(lltv);
        return adjustedValue.wDivDown(borrowedAmount);
    }

    /// @notice Calculate max seizable collateral and repayable debt
    function calculateLiquidationLimits(
        uint256 collateralAmount,
        uint256 borrowedAmount,
        uint256 maxLiquidationRatio
    ) internal pure returns (uint256 maxSeizableCollateral, uint256 maxRepayableDebt) {
        maxRepayableDebt = borrowedAmount.wMulDown(maxLiquidationRatio);
        maxSeizableCollateral = collateralAmount.wMulDown(maxLiquidationRatio);
    }
}
