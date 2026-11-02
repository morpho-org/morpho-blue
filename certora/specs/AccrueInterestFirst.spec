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

// Check that the variables written by accrueInterest (see AccrueInterestWrites.spec) and the borrow rate are not accessed before accrueInterest in functions that accrue interest.
rule noAccessBeforeAccrueInterest(method f, env e, calldataarg data) {
    // Set up the initial state.
    require !accrued;
    require !accessedBeforeAccrual;

    f@withrevert(e, data);

    assert accrued => !accessedBeforeAccrual;
}
