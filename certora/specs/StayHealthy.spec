// SPDX-License-Identifier: GPL-2.0-or-later
import "Health.spec";

// Check that without accruing interest, no interaction can put an healthy account into an unhealthy one.
// The liquidate function times out in this rule, but has been checked separately.
rule stayHealthy(env e, method f, calldataarg data)
filtered {
    f -> !f.isView &&
    f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector
}
{
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = Util.libId(marketParams);
    address user;

    // Assume that the position is healthy before the interaction.
    require isHealthy(marketParams, user);
    // Safe require because of the invariants onlyEnabledLltv and lltvSmallerThanWad in ConsistentState.spec.
    require marketParams.lltv < 10^18;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    f(e, data);

    // Safe require because of the invariant sumBorrowSharesCorrect.
    require borrowShares(id, user) <= totalBorrowShares(id);

    bool stillHealthy = isHealthy(marketParams, user);
    assert !priceChanged => stillHealthy;
}

// The liquidate case for the stayHealthy rule, assuming no bad debt realization, otherwise it times out.
// This particular rule makes the following assumptions:
//   - the market of the liquidation is the market of the user, see the *DifferentMarkets rule,
//   - there is still some borrow on the market after liquidation, see the *LastBorrow rule.
rule stayHealthyLiquidate(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssets, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);
    address user;

    // Assume the invariant initially.
    require isHealthy(marketParams, user);

    uint256 debtSharesBefore = borrowShares(id, user);
    uint256 debtAssetsBefore = summaryMulDivUp(debtSharesBefore, virtualTotalBorrowAssets(id), virtualTotalBorrowShares(id));
    // Safe require because of the invariants onlyEnabledLltv and lltvSmallerThanWad in ConsistentState.spec.
    require marketParams.lltv < 10^18;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    liquidate(e, marketParams, borrower, seizedAssets, 0, data);
    require !priceChanged;

    // Safe require because of the invariant sumBorrowSharesCorrect.
    require borrowShares(id, user) <= totalBorrowShares(id);
    // Assume that there is still some borrow on the market after liquidation.
    require totalBorrowAssets(id) > 0;
    // Assume no bad debt realization.
    require collateral(id, borrower) > 0;

    assert user != borrower;
    assert debtSharesBefore == borrowShares(id, user);
    assert debtAssetsBefore >= summaryMulDivUp(debtSharesBefore, virtualTotalBorrowAssets(id), virtualTotalBorrowShares(id));

    bool stillHealthy = isHealthy(marketParams, user);
    require !priceChanged;
    assert stillHealthy;
}

rule stayHealthyLiquidateDifferentMarkets(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssets, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);
    address user;
    MorphoHarness.MarketParams liquidationMarketParams;

    // Assume the invariant initially.
    require isHealthy(marketParams, user);

    // Safe require because of the invariants onlyEnabledLltv and lltvSmallerThanWad in ConsistentState.spec.
    require marketParams.lltv < 10^18;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;
    // Assume that the liquidation is on a different market.
    require liquidationMarketParams != marketParams;

    liquidate(e, liquidationMarketParams, borrower, seizedAssets, 0, data);
    require !priceChanged;

    // Safe require because of the invariant sumBorrowSharesCorrect.
    require borrowShares(id, user) <= totalBorrowShares(id);

    bool stillHealthy = isHealthy(marketParams, user);
    require !priceChanged;
    assert stillHealthy;
}

rule stayHealthyLiquidateLastBorrow(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssets, bytes data) {
    MorphoHarness.Id id = Util.libId(marketParams);
    address user;

    // Assume the invariant initially.
    require isHealthy(marketParams, user);

    // Safe require because of the invariants onlyEnabledLltv and lltvSmallerThanWad in ConsistentState.spec.
    require marketParams.lltv < 10^18;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    liquidate(e, marketParams, borrower, seizedAssets, 0, data);
    require !priceChanged;

    // Safe require because of the invariant sumBorrowSharesCorrect.
    require borrowShares(id, user) <= totalBorrowShares(id);
    // Assume that there is no remaining borrow on the market after liquidation.
    require totalBorrowAssets(id) == 0;

    bool stillHealthy = isHealthy(marketParams, user);
    require !priceChanged;
    assert stillHealthy;
}
