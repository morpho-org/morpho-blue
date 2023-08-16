// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MathLib} from "./MathLib.sol";

/// @dev Oracle price scale.
uint256 constant ORACLE_PRICE_SCALE = 1e36;

library PriceLib {
    using MathLib for uint256;

    function toCollateralDown(uint256 borrowableAssets, uint256 collateralPrice) internal pure returns (uint256) {
        return borrowableAssets.mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
    }

    function toCollateralUp(uint256 borrowableAssets, uint256 collateralPrice) internal pure returns (uint256) {
        return borrowableAssets.mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
    }

    function toBorrowableDown(uint256 collateralAssets, uint256 collateralPrice) internal pure returns (uint256) {
        return collateralAssets.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
    }

    function toBorrowableUp(uint256 collateralAssets, uint256 collateralPrice) internal pure returns (uint256) {
        return collateralAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
    }
}
