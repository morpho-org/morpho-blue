// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
}

persistent ghost mathint sstoreCount;

persistent ghost mathint expectedSstoreCount;

hook ALL_SSTORE(uint _, uint _) {
    sstoreCount = sstoreCount + 1;
}

hook Sstore market[KEY MorphoHarness.Id _].totalSupplyAssets uint128 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore market[KEY MorphoHarness.Id _].totalSupplyShares uint128 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore market[KEY MorphoHarness.Id _].totalBorrowAssets uint128 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore market[KEY MorphoHarness.Id _].lastUpdate uint128 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore position[KEY MorphoHarness.Id _][KEY address _].supplyShares uint256 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

// Check that accrueInterest writes no storage variable other than the totalSupplyAssets, totalSupplyShares, totalBorrowAssets and lastUpdate of markets, and the supplyShares of positions.
rule accrueInterestWrites(env e, MorphoHarness.MarketParams marketParams) {
    // Set up the initial state.
    require sstoreCount == 0;
    require expectedSstoreCount == 0;

    accrueInterest(e, marketParams);

    assert sstoreCount == expectedSstoreCount;
}
