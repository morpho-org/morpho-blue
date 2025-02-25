// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;

    function borrowShares(MorphoLiquidateHarness.Id, address) external returns (uint256) envfree;
    function collateral(MorphoLiquidateHarness.Id, address) external returns (uint256) envfree;
    function totalBorrowShares(MorphoLiquidateHarness.Id) external returns (uint256) envfree;
    function totalBorrowAssets(MorphoLiquidateHarness.Id) external returns (uint256) envfree;
    function virtualAssets() external returns uint256 envfree;
    function virtualShares() external returns uint256 envfree;
    function virtualTotalBorrowAssets(MorphoLiquidateHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoLiquidateHarness.Id) external returns uint256 envfree;
    function liquidateView(MorphoLiquidateHarness.MarketParams, address, uint256, uint256) external returns (MorphoLiquidateHarness.LiquidateReturnParams) envfree;

    function Util.wad() external returns (uint256) envfree;
    function Util.libId(MorphoLiquidateHarness.MarketParams) external returns (MorphoLiquidateHarness.Id) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;

    function _.price() external => constantPrice expect uint256;
}

persistent ghost uint256 constantPrice;

rule liquidateImprovePosition(MorphoLiquidateHarness.MarketParams marketParams, address borrower, uint256 seizedAssets, uint256 repaidShares) {
    MorphoLiquidateHarness.Id id = Util.libId(marketParams);

    uint256 borrowerShares = borrowShares(id, borrower);
    uint256 borrowerCollateral = collateral(id, borrower);

    // Safe require because of the sumBorrowSharesCorrect invariant.
    require borrowerShares <= totalBorrowShares(id);

    MorphoLiquidateHarness.LiquidateReturnParams p;
    p = liquidateView(marketParams, borrower, seizedAssets, repaidShares);

    // Let borrowerAssets = borrowerShares * virtualTotalBorrowAssets(id) / virtualTotalBorrowShares(id)
    // and borrowerCollateralQuoted = borrowerCollateral * constantPrice / Util.oraclePriceScale()
    // Then the following line is essentially borrowerAssets / borrowerCollateralQuoted < 1 / LIF
    require borrowerCollateral * constantPrice * virtualTotalBorrowShares(id) * Util.wad() > borrowerShares * Util.oraclePriceScale() * virtualTotalBorrowAssets(id) * p.liquidationIncentiveFactor;

    // Prove that the ratio of shares of debt over collateral is smaller after the liquidation.
    assert borrowerShares * p.newBorrowerCollateral >= p.newBorrowerShares * borrowerCollateral;

    // Prove that the value of borrow shares is smaller after the liquidation.
    // Note that this is only shown for the case where there are still borrow positions on the markets.
    assert p.newTotalAssets > 0 => (p.newTotalShares + virtualShares()) * virtualTotalBorrowAssets(id) >= (p.newTotalAssets + virtualAssets()) * virtualTotalBorrowShares(id);
}
