// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;

    function lastUpdate(MorphoHarness.Id) external returns (uint256) envfree;
    function borrowShares(MorphoHarness.Id, address) external returns (uint256) envfree;
    function collateral(MorphoHarness.Id, address) external returns (uint256) envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns (uint256) envfree;
    function totalBorrowAssets(MorphoHarness.Id) external returns (uint256) envfree;
    function virtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;

    function Util.libId(MorphoHarness.MarketParams) external returns (MorphoHarness.Id) envfree;
    function Util.lif(uint256) external returns (uint256) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;
    function Util.wad() external returns (uint256) envfree;

    function Morpho._isHealthy(MorphoHarness.MarketParams memory, MorphoHarness.Id, address) internal returns (bool) => NONDET;
    function Morpho._accrueInterest(MorphoHarness.MarketParams memory, MorphoHarness.Id) internal => NONDET;

    function _.price() external => constantPrice expect uint256;
}

persistent ghost uint256 constantPrice;

// Check that for a position with LTV < 1 / LIF, its health improves after a liquidation.
rule liquidateImprovePosition(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssetsInput, uint256 repaidSharesInput, bytes data) {
    // Assume no callback.
    require data.length == 0;

    MorphoHarness.Id id = Util.libId(marketParams);

    // We place ourselves at the last block for getting the following variables.
    require lastUpdate(id) == e.block.timestamp;

    uint256 borrowerShares = borrowShares(id, borrower);
    // Safe require because of the sumBorrowSharesCorrect invariant.
    require borrowerShares <= totalBorrowShares(id);

    uint256 borrowerCollateral = collateral(id, borrower);
    uint256 lif = Util.lif(marketParams.lltv);
    uint256 virtualTotalAssets = virtualTotalBorrowAssets(id);
    uint256 virtualTotalShares = virtualTotalBorrowShares(id);

    // Let borrowerAssets = borrowerShares * virtualTotalAssets / virtualTotalShares
    // and borrowerCollateralQuoted = borrowerCollateral * constantPrice / Util.oraclePriceScale()
    // then the following line is the assumption borrowerAssets / borrowerCollateralQuoted < 1 / LIF.
    require borrowerCollateral * constantPrice * virtualTotalShares * Util.wad() > borrowerShares * Util.oraclePriceScale() * virtualTotalAssets * lif;

    uint256 seizedAssets;
    (seizedAssets, _) = liquidate(e, marketParams, borrower, seizedAssetsInput, repaidSharesInput, data);

    uint256 newBorrowerShares = borrowShares(id, borrower);
    uint256 newBorrowerCollateral = collateral(id, borrower);
    uint256 repaidShares = assert_uint256(borrowerShares - newBorrowerShares);
    uint256 newVirtualTotalAssets = virtualTotalBorrowAssets(id);
    uint256 newVirtualTotalShares = virtualTotalBorrowShares(id);

    // Hint for the prover to show that there is no bad debt realization.
    assert newBorrowerCollateral != 0;
    // Hint for the prover about the ratio used to close the position.
    assert repaidShares * borrowerCollateral >= seizedAssets * borrowerShares;
    // Prove that the ratio of shares of debt over collateral is smaller after the liquidation.
    assert borrowerShares * newBorrowerCollateral >= newBorrowerShares * borrowerCollateral;
    // Prove that the value of borrow shares is smaller after the liquidation.
    // Note that this is only shown for the case where there are still borrow positions on the markets.
    assert totalBorrowAssets(id) > 0 => newVirtualTotalShares * virtualTotalAssets >= newVirtualTotalAssets * virtualTotalShares;
}
