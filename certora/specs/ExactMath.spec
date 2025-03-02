// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function feeRecipient() external returns address envfree;
    function supplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function virtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;

    function Util.maxFee() external returns uint256 envfree;
    function Util.libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;

    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => NONDET;
    function _.onMorphoSupply(uint256 assets, bytes data) external => HAVOC_ECF;
}

// Check that when not accruing interest, and when repaying all, the borrow exchange rate is at least reset to the initial exchange rate.
// More details on the purpose of this rule in ExchangeRate.spec.
rule repayAllResetsBorrowExchangeRate(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);
    // Safe require because this invariant is checked in ConsistentState.spec
    require fee(id) <= Util.maxFee();

    mathint assetsBefore = virtualTotalBorrowAssets(id);
    mathint sharesBefore = virtualTotalBorrowShares(id);

    // Assume no interest as it would increase the borrowed assets.
    require lastUpdate(id) == e.block.timestamp;

    mathint repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onBehalf, data);

    // Check the case where the market is fully repaid.
    require repaidAssets >= assetsBefore;

    mathint assetsAfter = virtualTotalBorrowAssets(id);
    mathint sharesAfter = virtualTotalBorrowShares(id);

    assert assetsAfter == 1;
    // There are at least as many shares as virtual shares, by definition of virtualTotalBorrowShares.
}

// There should be no profit from supply followed immediately by withdraw.
rule supplyWithdraw() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = Util.libId(marketParams);
    env e1;
    env e2;
    address onBehalf;

    // Assume that interactions happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Assume that the user starts without any supply position.
    require supplyShares(id, onBehalf) == 0;
    // Assume that the user is not the fee recipient, otherwise the gain can come from the fee.
    require onBehalf != feeRecipient();
    // Safe require because timestamps cannot realistically be that large.
    require e1.block.timestamp < 2^128;

    uint256 supplyAssets; uint256 supplyShares; bytes data;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e1, marketParams, supplyAssets, supplyShares, onBehalf, data);

    // Hints for the prover.
    assert suppliedAssets * (virtualTotalSupplyShares(id) - suppliedShares) >= suppliedShares * (virtualTotalSupplyAssets(id) - suppliedAssets);
    assert suppliedAssets * virtualTotalSupplyShares(id) >= suppliedShares * virtualTotalSupplyAssets(id);

    uint256 withdrawAssets; uint256 withdrawShares; address receiver;
    uint256 withdrawnAssets;
    withdrawnAssets, _ = withdraw(e2, marketParams, withdrawAssets, withdrawShares, onBehalf, receiver);

    assert withdrawnAssets <= suppliedAssets;
}

// There should be no profit from borrow followed immediately by repaying all.
rule borrowRepay() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = Util.libId(marketParams);
    address onBehalf;
    env e1;
    env e2;

    // Assume interactions happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Assume that the user starts without any borrow position.
    require borrowShares(id, onBehalf) == 0;
    // Safe require because timestamps cannot realistically be that large.
    require e1.block.timestamp < 2^128;

    uint256 borrowAssets; uint256 borrowShares; address receiver;
    uint256 borrowedAssets;
    uint256 borrowedShares;
    borrowedAssets, borrowedShares = borrow(e2, marketParams, borrowAssets, borrowShares, onBehalf, receiver);

    // Hints for the prover.
    assert borrowedAssets * (virtualTotalBorrowShares(id) - borrowedShares) <= borrowedShares * (virtualTotalBorrowAssets(id) - borrowedAssets);
    assert borrowedAssets * virtualTotalBorrowShares(id) <= borrowedShares * virtualTotalBorrowAssets(id);

    bytes data;
    uint256 repaidAssets;
    repaidAssets, _ = repay(e1, marketParams, 0, borrowedShares, onBehalf, data);

    assert borrowedAssets <= repaidAssets;
}
