// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MathLib, WAD} from "./MathLib.sol";
import {PriceLib} from "./PriceLib.sol";
import {UtilsLib} from "./UtilsLib.sol";

/// @dev Liquidation cursor.
uint256 constant LIQUIDATION_CURSOR = 0.3e18;
/// @dev Max liquidation incentive factor.
uint256 constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

library LiquidationLib {
    using MathLib for uint256;
    using PriceLib for uint256;
    using UtilsLib for uint256;

    /// @dev The liquidation incentive factor is min(maxIncentiveFactor, 1/(1 - cursor(1 - lltv))).
    function incentiveFactor(uint256 lltv) internal pure returns (uint256) {
        return MAX_LIQUIDATION_INCENTIVE_FACTOR.min(WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
    }

    function toMaxBorrowable(uint256 collateralAssets, uint256 collateralPrice, uint256 lltv)
        internal
        pure
        returns (uint256)
    {
        return collateralAssets.toBorrowableDown(collateralPrice).wMulDown(lltv);
    }

    function toMinCollateral(uint256 borrowableAssets, uint256 collateralPrice, uint256 lltv)
        internal
        pure
        returns (uint256)
    {
        return borrowableAssets.wDivUp(lltv).toCollateralUp(collateralPrice);
    }

    function toRepaid(uint256 seized, uint256 collateralPrice, uint256 lltv) internal pure returns (uint256) {
        return seized.toBorrowableUp(collateralPrice).wDivUp(incentiveFactor(lltv));
    }

    function toSeized(uint256 repaid, uint256 collateralPrice, uint256 lltv) internal pure returns (uint256) {
        return repaid.wMulDown(incentiveFactor(lltv)).toCollateralDown(collateralPrice);
    }
}
