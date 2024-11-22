// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function liquidateView(MorphoLiquidateHarness.MarketParams, uint256, uint256, uint256) external returns (uint256, uint256, uint256, uint256) envfree;

    function extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;

    function Util.wad() external returns (uint256) envfree;
    function Util.libId(MorphoLiquidateHarness.MarketParams) external returns (MorphoLiquidateHarness.Id) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns (uint256) => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns (uint256) => summaryMulDivUp(a,b,c);
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    return require_uint256((x * y) / d);
}

rule liquidateImprovePosition(MorphoLiquidateHarness.MarketParams marketParams, uint256 seizedAssetsInput, uint256 repaidSharesInput) {
    uint256 collateralPrice;

    // uint256 borrowerShares;
    // uint256 borrowerCollateral;

    // require borrowerShares < totalShares
    // require borrowerAssets < totalAssets

    // require LTV < 1 / LIF;

    require seizedAssetsInput > 0 && repaidSharesInput == 0;

    uint256 seizedAssets;
    uint256 repaidShares;
    uint256 repaidAssets;
    uint256 lif;
    (seizedAssets, repaidShares, repaidAssets, lif) = liquidateView(marketParams, seizedAssetsInput, repaidSharesInput, collateralPrice);

    assert summaryMulDivDown(lif, repaidAssets, Util.wad()) >= summaryMulDivUp(seizedAssets, collateralPrice, Util.oraclePriceScale());

    // assert repaidShares * borrowerCollateral > seizedAssets * borrowerShares;
}
