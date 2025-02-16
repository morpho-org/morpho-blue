// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;

    function lastUpdate(MorphoHarness.Id) external returns (uint256) envfree;
    function borrowShares(MorphoHarness.Id, address) external returns (uint256) envfree;
    function collateral(MorphoHarness.Id, address) external returns (uint256) envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns (uint256) envfree;
    function virtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;

    function Util.libId(MorphoHarness.MarketParams) external returns (MorphoHarness.Id) envfree;
    function Util.lif(uint256) external returns (uint256) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;
    function Util.wad() external returns (uint256) envfree;

    function Morpho._isHealthy(MorphoHarness.MarketParams memory, MorphoHarness.Id,address) internal returns (bool) => NONDET;
    function Morpho._accrueInterest(MorphoHarness.MarketParams memory, MorphoHarness.Id) internal => NONDET;

    function _.price() external => constantPrice expect uint256;
}

persistent ghost uint256 constantPrice;

rule liquidateImprovePosition(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssetsInput, uint256 repaidSharesInput, bytes data) {
    // Assume no callback for simplicity.
    require data.length == 0;

    MorphoHarness.Id id = Util.libId(marketParams);

    // We place ourselves at the last block for getting the following variables.
    require lastUpdate(id) == e.block.timestamp;

    uint256 borrowerShares = borrowShares(id, borrower);
    require borrowerShares <= totalBorrowShares(id);

    uint256 borrowerCollateral = collateral(id, borrower);
    uint256 lif = Util.lif(marketParams.lltv);
    uint256 virtualTotalAssets = virtualTotalBorrowAssets(id);
    uint256 virtualTotalShares = virtualTotalBorrowShares(id);

    require borrowerCollateral * constantPrice * virtualTotalAssets * Util.wad() > borrowerShares * Util.oraclePriceScale() * virtualTotalShares * lif;

    uint256 seizedAssets;
    uint256 repaidAssets;
    (seizedAssets, repaidAssets) = liquidate(e, marketParams, borrower, seizedAssetsInput, repaidSharesInput, data);
    assert repaidAssets * lif * Util.oraclePriceScale() >= seizedAssets * constantPrice * Util.wad();

    uint256 newBorrowerShares = borrowShares(id, borrower);
    uint256 newBorrowerCollateral = collateral(id, borrower);
    uint256 repaidShares = assert_uint256(borrowerShares - newBorrowerShares);
    uint256 newVirtualTotalAssets = virtualTotalBorrowAssets(id);
    uint256 newVirtualTotalShares = virtualTotalBorrowShares(id);

    require collateral(id, borrower) != 0;
    assert borrowerShares * newBorrowerCollateral >= newBorrowerShares * borrowerCollateral;
    assert  newVirtualTotalShares * virtualTotalAssets >= newVirtualTotalAssets * virtualTotalShares;
}
