// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function isAuthorized(address, address user) external returns bool envfree;

    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function isHealthy(MorphoHarness.MarketParams, address user) external returns bool envfree;

    function _.price() external => mockPrice() expect uint256;
    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivUp(a,b,c);
    function UtilsLib.min(uint256 a, uint256 b) internal returns uint256 => summaryMin(a,b);
}

ghost uint256 lastPrice;
ghost bool priceChanged;

function mockPrice() returns uint256 {
    uint256 somePrice;
    if (somePrice != lastPrice) {
        priceChanged = true;
        lastPrice = somePrice;
    }
    return somePrice;
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    require d != 0;
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    require d != 0;
    return require_uint256((x * y) / d);
}

function summaryMin(uint256 a, uint256 b) returns uint256 {
    return a < b ? a : b;
}

// Check that without accruing interest, no interaction can put an healthy account into an unhealthy one.
// This rule times out for liquidate, repay and borrow.
rule stayHealthy(env e, method f, calldataarg data)
filtered {
    f -> !f.isView &&
    f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector &&
    f.selector != sig:repay(MorphoHarness.MarketParams, uint256, uint256, address, bytes).selector &&
    f.selector != sig:borrow(MorphoHarness.MarketParams, uint256, uint256, address, address).selector
}
{
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = libId(marketParams);
    address user;

    // Assume that the position is healthy before the interaction.
    require isHealthy(marketParams, user);
    // Safe require because of the invariants onlyEnabledLltv and lltvSmallerThanWad in ConsistentState.spec.
    require marketParams.lltv < 10^18;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    priceChanged = false;
    f(e, data);

    // Safe require because of the invariant sumBorrowSharesCorrect.
    require borrowShares(id, user) <= totalBorrowShares(id);

    bool stillHealthy = isHealthy(marketParams, user);
    assert !priceChanged => stillHealthy;
}

// Check that users cannot lose collateral by unauthorized parties except in case of an unhealthy position.
rule healthyUserCannotLoseCollateral(env e, method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = libId(marketParams);
    address user;

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;
    // Assume that the user is healthy.
    require isHealthy(marketParams, user);

    mathint collateralBefore = collateral(id, user);

    priceChanged = false;
    f(e, data);

    mathint collateralAfter = collateral(id, user);

    assert !priceChanged => collateralAfter >= collateralBefore;
}

// Check that users without collateral also have no debt.
// This invariant ensures that bad debt realization cannot be bypassed.
invariant alwaysCollateralized(MorphoHarness.Id id, address borrower)
    borrowShares(id, borrower) != 0 => collateral(id, borrower) != 0;
