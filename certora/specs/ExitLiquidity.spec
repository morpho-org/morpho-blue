// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function supplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function virtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function libMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function libMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

// Check that it's not possible to withdraw more assets than what the user owns.
rule withdrawLiquidity(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    env e;
    MorphoHarness.Id id = libId(marketParams);

    // Assume no interest as it would increase the total supply assets.
    require lastUpdate(id) == e.block.timestamp;

    uint256 initialShares = supplyShares(id, onBehalf);
    uint256 initialTotalSupply = virtualTotalSupplyAssets(id);
    uint256 initialTotalSupplyShares = virtualTotalSupplyShares(id);
    uint256 ownedAssets = libMulDivDown(initialShares, initialTotalSupply, initialTotalSupplyShares);

    uint256 withdrawnAssets;
    withdrawnAssets, _ = withdraw(e, marketParams, assets, shares, onBehalf, receiver);

    assert withdrawnAssets <= ownedAssets;
}

// Check that it's not possible to withdraw more collateral than what the user owns.
rule withdrawCollateralLiquidity(MorphoHarness.MarketParams marketParams, uint256 withdrawnAssets, address onBehalf, address receiver) {
    env e;
    MorphoHarness.Id id = libId(marketParams);

    uint256 ownedAssets = collateral(id, onBehalf);

    withdrawCollateral(e, marketParams, withdrawnAssets, onBehalf, receiver);

    assert withdrawnAssets <= ownedAssets;
}

// Check than when repaying the full outstanding debt requires more assets than what the user owes.
rule repayLiquidity(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    env e;
    MorphoHarness.Id id = libId(marketParams);

    // Assume no interest as it would increase the total borrowed assets.
    require lastUpdate(id) == e.block.timestamp;

    uint256 initialShares = borrowShares(id, onBehalf);
    uint256 initialTotalBorrow = virtualTotalBorrowAssets(id);
    uint256 initialTotalBorrowShares = virtualTotalBorrowShares(id);
    uint256 owedAssets = libMulDivUp(initialShares, initialTotalBorrow, initialTotalBorrowShares);

    uint256 repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onBehalf, data);

    // Assume a full repay.
    require borrowShares(id, onBehalf) == 0;

    assert repaidAssets >= owedAssets;
}
