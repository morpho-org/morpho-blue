// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;

    function market_(MorphoLiquidateHarness.Id) external returns (MorphoLiquidateHarness.Market) envfree;
    function virtualTotalBorrowAssets(MorphoLiquidateHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoLiquidateHarness.Id) external returns uint256 envfree;
    function liquidateView(MorphoLiquidateHarness.MarketParams, uint256, uint256, uint256) external returns (uint256, uint256, uint256, uint256) envfree;

    function Util.wad() external returns (uint256) envfree;
    function Util.libId(MorphoLiquidateHarness.MarketParams) external returns (MorphoLiquidateHarness.Id) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns (uint256) => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns (uint256) => summaryMulDivUp(a,b,c);
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Todo: why is this require ok ?
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Todo: why is this require ok ?
    return require_uint256((x * y) / d);
}

function wDivDown(uint256 x, uint256 y) returns uint256 {
    return summaryMulDivDown(x, Util.wad(), y);
}

rule liquidateImprovePosition(MorphoLiquidateHarness.MarketParams marketParams, uint256 seizedAssetsInput, uint256 repaidSharesInput) {
    MorphoLiquidateHarness.Id id = Util.libId(marketParams);

    // TODO: use a fixed price oracle instead of passing it to liquidateView.
    uint256 collateralPrice;
    require collateralPrice > 0;

    // TODO: take those directly from the borrower, and manage accrue interest.
    uint256 borrowerShares;
    uint256 borrowerCollateral;

    require borrowerShares <= market_(id).totalBorrowShares;
    uint256 borrowerAssets = summaryMulDivUp(borrowerShares, virtualTotalBorrowAssets(id), virtualTotalBorrowShares(id));
    require borrowerAssets > 0;

    require (seizedAssetsInput > 0 && repaidSharesInput == 0) || (seizedAssetsInput == 0 && repaidSharesInput > 0);

    uint256 seizedAssets;
    uint256 repaidShares;
    uint256 repaidAssets;
    uint256 lif;
    (seizedAssets, repaidShares, repaidAssets, lif) = liquidateView(marketParams, seizedAssetsInput, repaidSharesInput, collateralPrice);
    require repaidAssets > 0;

    uint256 borrowerCollateralQuoted = summaryMulDivUp(borrowerCollateral, collateralPrice, Util.oraclePriceScale());
    require borrowerCollateralQuoted >= summaryMulDivUp(lif, borrowerAssets, Util.wad());
    assert wDivDown(borrowerCollateralQuoted, borrowerAssets) >= lif;

    uint256 seizedCollateralQuoted = summaryMulDivUp(seizedAssets, collateralPrice, Util.oraclePriceScale());
    assert summaryMulDivDown(lif, repaidAssets, Util.wad()) >= seizedCollateralQuoted;
    assert lif >= wDivDown(seizedCollateralQuoted, repaidAssets);

    // assert repaidShares * borrowerCollateral > seizedAssets * borrowerShares;
}
