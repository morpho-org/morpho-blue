// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;
    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function virtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivUp(a,b,c);
    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => NONDET;
    function _.onMorphoSupply(uint256 assets, bytes data) external => HAVOC_ECF;

    function maxFee() external returns uint256 envfree;
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    return require_uint256((x * y) / d);
}

// Check that when not accruing interest, and when repaying all, the borrow ratio is at least reset to the initial ratio.
// More details on the purpose of this rule in RatioMath.spec.
rule repayAllResetsBorrowRatio(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onbehalf, bytes data) {
    MorphoHarness.Id id = libId(marketParams);
    // Safe require because this invariant is checked in ConsistentState.spec
    require fee(id) <= maxFee();

    mathint assetsBefore = virtualTotalBorrowAssets(id);
    mathint sharesBefore = virtualTotalBorrowShares(id);

    // Assume no interest as it would increase the borrowed assets.
    require lastUpdate(id) == e.block.timestamp;

    mathint repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onbehalf, data);

    // Check the case where the market is fully repaid.
    require repaidAssets >= assetsBefore;

    mathint assetsAfter = virtualTotalBorrowAssets(id);
    mathint sharesAfter = virtualTotalBorrowShares(id);

    assert assetsAfter == 1;
    // There are at least as many shares as virtual shares.
}

// There should be no profit from supply followed immediately by withdraw.
rule supplyWithdraw() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = libId(marketParams);
    uint256 assets;
    uint256 shares;
    address onbehalf;
    address receiver;
    bytes data;
    env e1;
    env e2;

    // Assume that interactions to happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Safe require because timestamps cannot realistically be that large.
    require e1.block.timestamp < 2^128;

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e1, marketParams, assets, shares, onbehalf, data);

    // Hints for the prover.
    assert suppliedAssets * (virtualTotalSupplyShares(id) - suppliedShares) >= suppliedShares * (virtualTotalSupplyAssets(id) - suppliedAssets);
    assert suppliedAssets * virtualTotalSupplyShares(id) >= suppliedShares * virtualTotalSupplyAssets(id);

    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    withdrawnAssets, withdrawnShares = withdraw(e2, marketParams, 0, suppliedShares, onbehalf, receiver);

    assert withdrawnShares == suppliedShares;
    assert withdrawnAssets <= suppliedAssets;
}

// There should be no profit from withdraw followed immediately by supply.
rule withdrawSupply() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = libId(marketParams);
    uint256 assets;
    uint256 shares;
    address onbehalf;
    address receiver;
    bytes data;
    env e1;
    env e2;

    // Assume interactions to happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Safe require because timestamps cannot realistically be that large.
    require e1.block.timestamp < 2^128;

    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    withdrawnAssets, withdrawnShares = withdraw(e2, marketParams, assets, shares, onbehalf, receiver);

    // Hints for the prover.
    assert withdrawnAssets * (virtualTotalSupplyShares(id) + withdrawnShares) <= withdrawnShares * (virtualTotalSupplyAssets(id) + withdrawnAssets);
    assert withdrawnAssets * virtualTotalSupplyShares(id) <= withdrawnShares * virtualTotalSupplyAssets(id);

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e1, marketParams, withdrawnAssets, 0, onbehalf, data);

    assert suppliedAssets == withdrawnAssets && withdrawnShares >= suppliedShares;
}

rule borrowRepay() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = libId(marketParams);
    uint256 assets;
    uint256 shares;
    address onbehalf;
    address receiver;
    bytes data;
    env e1;
    env e2;

    // Assume interactions to happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Safe require because timestamps cannot realistically be that large.
    require e1.block.timestamp < 2^128;

    uint256 borrowedAssets;
    uint256 borrowedShares;
    borrowedAssets, borrowedShares = borrow(e2, marketParams, assets, shares, onbehalf, receiver);

    // Hints for the prover.
    assert borrowedAssets * (virtualTotalBorrowShares(id) + borrowedShares) <= borrowedShares * (virtualTotalBorrowAssets(id) + borrowedAssets);
    assert borrowedAssets * virtualTotalBorrowShares(id) <= borrowedShares * virtualTotalBorrowAssets(id);

    uint256 repaidAssets;
    uint256 repaidShares;
    repaidAssets, repaidShares = repay(e1, marketParams, borrowedAssets, 0, onbehalf, data);

    assert repaidAssets == borrowedAssets && borrowedShares >= repaidShares;
}
