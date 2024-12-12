// SPDX-License-Identifier: GPL-2.0-or-later

import "Health.spec";

methods {
    function Util.lif(uint256) external returns (uint256) envfree;
    function Util.oraclePriceScale() external returns (uint256) envfree;
    function Util.wad() external returns (uint256) envfree;
}

rule liquidateImprovePosition(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssetsInput, uint256 repaidSharesInput, bytes data) {
    // Assume no callback for simplicity.
    require data.length == 0;

    MorphoHarness.Id id = Util.libId(marketParams);

    // We place ourselves at the last block for getting the following variables.
    require lastUpdate(id) == e.block.timestamp;

    uint256 borrowerShares = borrowShares(id, borrower);
    require borrowerShares <= totalBorrowShares(id);

    uint256 borrowerCollateral = collateral(id, borrower);
    uint256 collateralPrice = mockPrice();
    uint256 lif = Util.lif(marketParams.lltv);

    uint256 borrowerAssets = summaryMulDivUp(borrowerShares, virtualTotalBorrowAssets(id), virtualTotalBorrowShares(id));
    uint256 borrowerCollateralQuoted = summaryMulDivDown(borrowerCollateral, collateralPrice, Util.oraclePriceScale());

    require summaryMulDivUp(lif, borrowerAssets, Util.wad()) < borrowerCollateralQuoted;
    assert borrowerCollateral * collateralPrice * virtualTotalBorrowShares(id) * Util.wad() > borrowerShares * Util.oraclePriceScale() * virtualTotalBorrowAssets(id) * lif;

    uint256 seizedAssets;
    uint256 repaidAssets;
    (seizedAssets, repaidAssets) = liquidate(e, marketParams, borrower, seizedAssetsInput, repaidSharesInput, data);

    uint256 newBorrowerShares = borrowShares(id, borrower);
    uint256 repaidShares = assert_uint256(borrowerShares - newBorrowerShares);

    require !priceChanged;
    require collateral(id, borrower) != 0;
    assert repaidShares * borrowerCollateral >= seizedAssets * borrowerShares;
    // assert borrowerShares * newBorrowerCollateral >= newBorrowerShares * borrowerCollateral;
    // assert newTotalShares * OldVirtualTotalBorrowAssets >= newTotalAssets * OldVirtualTotalBorrowShares;

}
