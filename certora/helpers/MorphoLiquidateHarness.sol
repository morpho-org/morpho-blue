// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./MorphoHarness.sol";

contract MorphoLiquidateHarness is MorphoHarness {
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;
    using SharesMathLib for uint256;

    constructor(address newOwner) MorphoHarness(newOwner) {}

    function liquidateView(MarketParams memory marketParams, uint256 seizedAssets, uint256 repaidShares)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        Id id = marketParams.id();

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

        return (seizedAssets, repaidShares, repaidAssets, liquidationIncentiveFactor);
    }
}
