// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;

    function market_(MorphoLiquidateHarness.Id) external returns (MorphoLiquidateHarness.Market) envfree;
    function virtualTotalBorrowAssets(MorphoLiquidateHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoLiquidateHarness.Id) external returns uint256 envfree;
    function liquidateView(MorphoLiquidateHarness.MarketParams, uint256, uint256) external returns (uint256, uint256, uint256, uint256) envfree;

    function Util.wad() external returns (uint256) envfree;
    function Util.libId(MorphoLiquidateHarness.MarketParams) external returns (MorphoLiquidateHarness.Id) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;

    function _.price() external => constantPrice expect uint256;
}

persistent ghost uint256 constantPrice;

rule liquidateImprovePosition(MorphoLiquidateHarness.MarketParams marketParams, uint256 seizedAssetsInput, uint256 repaidSharesInput) {
    MorphoLiquidateHarness.Id id = Util.libId(marketParams);

    // TODO: take those directly from the borrower, and manage accrue interest.
    uint256 borrowerShares;
    uint256 borrowerCollateral;

    require borrowerShares <= market_(id).totalBorrowShares;

    require (seizedAssetsInput > 0 && repaidSharesInput == 0) || (seizedAssetsInput == 0 && repaidSharesInput > 0);

    uint256 seizedAssets;
    uint256 repaidShares;
    uint256 repaidAssets;
    uint256 lif;
    (seizedAssets, repaidShares, repaidAssets, lif) = liquidateView(marketParams, seizedAssetsInput, repaidSharesInput);

    // Let borrowerAssets = borrowerShares * virtualTotalBorrowAssets(id) / virtualTotalBorrowShares(id)
    // and borrowerCollateralQuoted = borrowerCollateral * constantPrice / Util.oraclePriceScale()
    // Then the following line is essentially borrowerAssets / borrowerCollateralQuoted < 1 / lif
    require borrowerCollateral * constantPrice * virtualTotalBorrowShares(id) * Util.wad() > borrowerShares * Util.oraclePriceScale() * virtualTotalBorrowAssets(id) * lif;

    uint256 newBorrowerShares = require_uint256(borrowerShares - repaidShares);
    uint256 newTotalShares = require_uint256(virtualTotalBorrowShares(id) - repaidShares);
    mathint mathNewTotalAssets = virtualTotalBorrowAssets(id) - repaidAssets;
    uint256 newTotalAssets = assert_uint256(mathNewTotalAssets >= 0 ? mathNewTotalAssets : 0);

    uint256 newBorrowerCollateral = require_uint256(borrowerCollateral - seizedAssets);

    assert repaidShares * borrowerCollateral >= seizedAssets * borrowerShares;

    // Prove that the ratio of shares of debt over collateral is smaller after the liquidation.
    assert borrowerShares * newBorrowerCollateral >= newBorrowerShares * borrowerCollateral;
    // Prove that the value of borrow shares is smaller after the liquidation.
    assert newTotalShares * virtualTotalBorrowAssets(id) >= newTotalAssets * virtualTotalBorrowShares(id);
}
