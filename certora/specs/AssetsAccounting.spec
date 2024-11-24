// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function supplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function Util.libMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function Util.libMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function Util.libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

function expectedSupplyAssets(MorphoHarness.Id id, address user) returns uint256 {
    uint256 userShares = supplyShares(id, user);
    uint256 totalSupplyAssets = virtualTotalSupplyAssets(id);
    uint256 totalSupplyShares = virtualTotalSupplyShares(id);

    return Util.libMulDivDown(userShares, totalSupplyAssets, totalSupplyShares);
}

function expectedBorrowAssets(MorphoHarness.Id id, address user) returns uint256 {
    uint256 userShares = borrowShares(id, user);
    uint256 totalBorrowAssets = virtualTotalBorrowAssets(id);
    uint256 totalBorrowShares = virtualTotalBorrowShares(id);

    return Util.libMulDivUp(userShares, totalBorrowAssets, totalBorrowShares);
}

// Check that the assets supplied are greater than the increase in owned assets.
rule supplyAssetsAccounting(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);

    // Assume no interest as it would increase the total supply assets.
    require lastUpdate(id) == e.block.timestamp;
    // Safe require because of the sumSupplySharesCorrect invariant.
    require supplyShares(id, onBehalf) <= totalSupplyShares(id);

    uint256 ownedAssetsBefore = expectedSupplyAssets(id, onBehalf);

    uint256 suppliedAssets;
    suppliedAssets, _ = supply(e, marketParams, assets, shares, onBehalf, data);

    uint256 ownedAssets = expectedSupplyAssets(id, onBehalf);

    assert ownedAssetsBefore + suppliedAssets >= to_mathint(ownedAssets);
}

// Check that the assets withdrawn are less than the assets owned initially.
rule withdrawAssetsAccounting(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    MorphoHarness.Id id = Util.libId(marketParams);

    // Assume no interest as it would increase the total supply assets.
    require lastUpdate(id) == e.block.timestamp;

    uint256 ownedAssets = expectedSupplyAssets(id, onBehalf);

    uint256 withdrawnAssets;
    withdrawnAssets, _ = withdraw(e, marketParams, assets, shares, onBehalf, receiver);

    assert withdrawnAssets <= ownedAssets;
}

// Check that the increase of owed assets are greater than the borrowed assets.
rule borrowAssetsAccounting(env e, MorphoHarness.MarketParams marketParams, uint256 shares, address onBehalf, address receiver) {
    MorphoHarness.Id id = Util.libId(marketParams);

    // Assume no interest as it would increase the total borrowed assets.
    require lastUpdate(id) == e.block.timestamp;
    // Safe require because of the sumBorrowSharesCorrect invariant.
    require borrowShares(id, onBehalf) <= totalBorrowShares(id);

    uint256 owedAssetsBefore = expectedBorrowAssets(id, onBehalf);

    // The borrow call is restricted to shares as input to make it easier on the prover.
    uint256 borrowedAssets;
    borrowedAssets, _ = borrow(e, marketParams, 0, shares, onBehalf, receiver);

    uint256 owedAssets = expectedBorrowAssets(id, onBehalf);

    assert owedAssetsBefore + borrowedAssets <= to_mathint(owedAssets);
}

// Check that the assets repaid are greater than the assets owed initially.
rule repayAssetsAccounting(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);

    // Assume no interest as it would increase the total borrowed assets.
    require lastUpdate(id) == e.block.timestamp;

    uint256 owedAssets = expectedBorrowAssets(id, onBehalf);

    uint256 repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onBehalf, data);

    // Assume a full repay.
    require borrowShares(id, onBehalf) == 0;

    assert repaidAssets >= owedAssets;
}

// Check that the collateral assets supplied are equal to the increase of owned assets.
rule supplyCollateralAssetsAccounting(env e, MorphoHarness.MarketParams marketParams, uint256 suppliedAssets, address onBehalf, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);

    uint256 ownedAssetsBefore = collateral(id, onBehalf);

    supplyCollateral(e, marketParams, suppliedAssets, onBehalf, data);

    uint256 ownedAssets = collateral(id, onBehalf);

    assert ownedAssetsBefore + suppliedAssets == to_mathint(ownedAssets);
}

// Check that the collateral assets withdrawn are less than the assets owned initially.
rule withdrawCollateralAssetsAccounting(env e, MorphoHarness.MarketParams marketParams, uint256 withdrawnAssets, address onBehalf, address receiver) {
    MorphoHarness.Id id = Util.libId(marketParams);

    uint256 ownedAssets = collateral(id, onBehalf);

    withdrawCollateral(e, marketParams, withdrawnAssets, onBehalf, receiver);

    assert withdrawnAssets <= ownedAssets;
}
