// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./MorphoHarness.sol";

contract MorphoLiquidateHarness is MorphoHarness {
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using SharesMathLib for uint256;

    struct LiquidateReturnParams {
        uint256 repaidAssets;
        uint256 liquidationIncentiveFactor;
        uint256 newBorrowerShares;
        uint256 newTotalShares;
        uint256 newTotalAssets;
        uint256 newBorrowerCollateral;
    }

    constructor(address newOwner) MorphoHarness(newOwner) {}

    function virtualShares() external pure returns (uint256) {
        return SharesMathLib.VIRTUAL_SHARES;
    }

    function virtualAssets() external pure returns (uint256) {
        return SharesMathLib.VIRTUAL_ASSETS;
    }

    function liquidateView(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares
    ) external view returns (LiquidateReturnParams memory params) {
        Id id = marketParams.id();
        require(UtilsLib.exactlyOneZero(seizedAssets, repaidShares), ErrorsLib.INCONSISTENT_INPUT);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 liquidationIncentiveFactor = UtilsLib.min(
            MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - marketParams.lltv))
        );

        if (seizedAssets > 0) {
            uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);

            repaidShares = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor).toSharesUp(
                market[id].totalBorrowAssets, market[id].totalBorrowShares
            );
        } else {
            seizedAssets = repaidShares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares)
                .wMulDown(liquidationIncentiveFactor).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
        }
        uint256 repaidAssets = repaidShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);

        params.repaidAssets = repaidAssets;
        params.liquidationIncentiveFactor = liquidationIncentiveFactor;
        params.newBorrowerShares = position[id][borrower].borrowShares - repaidShares.toUint128();
        params.newTotalShares = market[id].totalBorrowShares - repaidShares.toUint128();
        params.newTotalAssets = UtilsLib.zeroFloorSub(market[id].totalBorrowAssets, repaidAssets).toUint128();
        params.newBorrowerCollateral = position[id][borrower].collateral - seizedAssets.toUint128();
    }
}
