// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function Morpho._accrueInterest(MorphoHarness.MarketParams memory, MorphoHarness.Id) internal => accrueInterestSummary();

    // Check that there are no call to borrowRate before an interest accrual.
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => borrowRateSummary() expect uint256;
}

persistent ghost bool accrued;

persistent ghost bool accessedBeforeAccrual;

function accrueInterestSummary() {
    accrued = true;
}

function recordAccess() {
    if (!accrued) {
        accessedBeforeAccrual = true;
    }
}

// Check that the borrow rate is not fetched before accruing interest.
function borrowRateSummary() returns uint256 {
    recordAccess();
    uint256 rate;
    return rate;
}

hook Sload uint128 _ market[KEY MorphoHarness.Id _].totalSupplyAssets {
    recordAccess();
}

hook Sstore market[KEY MorphoHarness.Id _].totalSupplyAssets uint128 _ {
    recordAccess();
}

hook Sload uint128 _ market[KEY MorphoHarness.Id _].totalSupplyShares {
    recordAccess();
}

hook Sstore market[KEY MorphoHarness.Id _].totalSupplyShares uint128 _ {
    recordAccess();
}

hook Sload uint128 _ market[KEY MorphoHarness.Id _].totalBorrowAssets {
    recordAccess();
}

hook Sstore market[KEY MorphoHarness.Id _].totalBorrowAssets uint128 _ {
    recordAccess();
}

// lastUpdate is read before accruing interest to check that the market is created, so only its writes are recorded.
// This is fine because:
// - before accruing interest, the only use of lastUpdate is to check that it is non-zero;
// - lastUpdate is not written before accruing interest (checked below);
// - the functions that accrue interest revert when lastUpdate is zero;
// - after accruing interest, lastUpdate is non-zero.
// So an outdated lastUpdate is never used in a function that accrues interest.
hook Sstore market[KEY MorphoHarness.Id _].lastUpdate uint128 _ {
    recordAccess();
}

hook Sload uint256 _ position[KEY MorphoHarness.Id _][KEY address _].supplyShares {
    recordAccess();
}

hook Sstore position[KEY MorphoHarness.Id _][KEY address _].supplyShares uint256 _ {
    recordAccess();
}

definition doesNotAccrueInterest(method f) returns bool =
    f.isView ||
    f.selector == sig:setOwner(address).selector ||
    f.selector == sig:enableIrm(address).selector ||
    f.selector == sig:enableLltv(uint256).selector ||
    f.selector == sig:setFeeRecipient(address).selector ||
    f.selector == sig:createMarket(MorphoHarness.MarketParams).selector ||
    f.selector == sig:supplyCollateral(MorphoHarness.MarketParams, uint256, address, bytes).selector ||
    f.selector == sig:flashLoan(address, uint256, bytes).selector ||
    f.selector == sig:setAuthorization(address, bool).selector ||
    f.selector == sig:setAuthorizationWithSig(MorphoHarness.Authorization, MorphoHarness.Signature).selector;

// Check that the listed functions never accrue interest, so they are not constrained by noAccessBeforeAccrueInterest.
rule listedFunctionsDoNotAccrueInterest(method f, env e, calldataarg data) filtered { f -> doesNotAccrueInterest(f) } {
    require !accrued;

    f@withrevert(e, data);

    assert !accrued;
}

// Check that the other functions always accrue interest when they don't revert, so the list above is exhaustive.
rule otherFunctionsAccrueInterest(method f, env e, calldataarg data) filtered { f -> !doesNotAccrueInterest(f) } {
    require !accrued;

    f(e, data);

    assert accrued;
}

// Check that the variables written by accrueInterest (see AccrueInterestWrites.spec) and the borrow rate are not accessed before accrueInterest in functions that accrue interest.
rule noAccessBeforeAccrueInterest(method f, env e, calldataarg data) {
    // Set up the initial state.
    require !accrued;
    require !accessedBeforeAccrual;

    f@withrevert(e, data);

    assert accrued => !accessedBeforeAccrual;
}
