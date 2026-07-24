// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function totalBorrowAssets(bytes32) external returns uint256 envfree;
    function totalBorrowShares(bytes32) external returns uint256 envfree;
    function virtualTotalBorrowAssets(bytes32) external returns uint256 envfree;
    function virtualTotalBorrowShares(bytes32) external returns uint256 envfree;
    function lastUpdate(bytes32) external returns uint256 envfree;
    function borrowShares(bytes32, address) external returns uint256 envfree;
    function collateral(bytes32, address) external returns uint256 envfree;
    function isAuthorized(address, address user) external returns bool envfree;
    function lastUpdate(bytes32) external returns uint256 envfree;

    function Util.libId(MorphoHarness.MarketParams) external returns bytes32 envfree;
    function isHealthy(MorphoHarness.MarketParams, address user) external returns bool envfree;

    function _.price() external => CONSTANT;
    function UtilsLib.min(uint256 a, uint256 b) internal returns uint256 => summaryMin(a, b);
}

function summaryMin(uint256 a, uint256 b) returns uint256 {
    return a < b ? a : b;
}

// Check that users cannot lose collateral by unauthorized parties except in case of an unhealthy position.
rule healthyUserCannotLoseCollateral(env e, method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.MarketParams marketParams;
    bytes32 id = Util.libId(marketParams);
    address user;

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;
    // Assume that the user is healthy.
    require isHealthy(marketParams, user);

    uint256 collateralBefore = collateral(id, user);

    f(e, data);

    assert collateral(id, user) >= collateralBefore;
}

// Check that users without collateral also have no debt.
// This invariant ensures that bad debt realization cannot be bypassed.
invariant alwaysCollateralized(bytes32 id, address borrower)
    borrowShares(id, borrower) != 0 => collateral(id, borrower) != 0;

// Checks that passing a seized amount input to liquidate leads to repaid shares S and repaid amount A such that liquidating instead with shares S also repays the amount A.
rule liquidateEquivalentInputDebtAndInputCollateral(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssets, bytes data) {
    bytes32 id = Util.libId(marketParams);

    // Assume no interest accrual to ease the verification.
    require lastUpdate(id) == e.block.timestamp;

    storage init = lastStorage;
    uint256 sharesBefore = borrowShares(id, borrower);

    uint256 repaidAssets1;
    _, repaidAssets1 = liquidate(e, marketParams, borrower, seizedAssets, 0, data);
    // Omit the bad debt realization case.
    require collateral(id, borrower) != 0;
    uint256 sharesAfter = borrowShares(id, borrower);
    uint256 repaidShares1 = assert_uint256(sharesBefore - sharesAfter);

    uint256 repaidAssets2;
    _, repaidAssets2 = liquidate(e, marketParams, borrower, 0, repaidShares1, data) at init;

    assert repaidAssets1 == repaidAssets2;
}
