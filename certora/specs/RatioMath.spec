methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function getVirtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function getFee(MorphoHarness.Id) external returns uint256 envfree;
    function getLastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivUp(a,b,c);
    function MathLib.wTaylorCompounded(uint256, uint256) internal returns uint256 => NONDET;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => HAVOC_ECF;

    function MAX_FEE() external returns uint256 envfree;
}

invariant feeInRange(MorphoHarness.Id id)
    getFee(id) <= MAX_FEE();

// This is a simple overapproximative summary, stating that it rounds in the right direction.
// The summary is checked by the specification in LibSummary.spec.
function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require result * d >= x * y;
    return result;
}

// This is a simple overapproximative summary, stating that it rounds in the right direction.
// The summary is checked by the specification in LibSummary.spec.
function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require result * d <= x * y;
    return result;
}

// Check that accrueInterest increases the value of supply shares.
rule accrueInterestIncreasesSupplyRatio(env e, MorphoHarness.MarketParams marketParams) {
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalSupplyAssets(id);
    mathint sharesBefore = getVirtualTotalSupplyShares(id);

    // The check is done for every market, not just for id.
    accrueInterest(e, marketParams);

    mathint assetsAfter = getVirtualTotalSupplyAssets(id);
    mathint sharesAfter = getVirtualTotalSupplyShares(id);

    // Check that ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter.
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

// Check that accrueInterest increases the value of borrow shares.
rule accrueInterestIncreasesBorrowRatio(env e, MorphoHarness.MarketParams marketParams) {
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    // The check is done for every marketParams, not just for id.
    accrueInterest(e, marketParams);

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    // Check that ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter.
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}


// Check that excepti for liquidate, every function increases the value of supply shares.
rule onlyLiquidateCanDecreaseSupplyRatio(env e, method f, calldataarg args)
filtered {
    f -> !f.isView && f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector
}
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalSupplyAssets(id);
    mathint sharesBefore = getVirtualTotalSupplyShares(id);

    // Interest is checked separately by the rules above.
    // Here we assume interest has already been accumulated for this block.
    require getLastUpdate(id) == e.block.timestamp;

    f(e,args);

    mathint assetsAfter = getVirtualTotalSupplyAssets(id);
    mathint sharesAfter = getVirtualTotalSupplyShares(id);

    // Check that ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

// Check that except when not accruing interest, every function is decreasing the value of borrow shares.
// The repay function is checked separately, see below.
// The liquidate function is not checked.
rule onlyAccrueInterestCanIncreaseBorrowRatio(env e, method f, calldataarg args)
filtered {
    f -> !f.isView &&
    f.selector != sig:repay(MorphoHarness.MarketParams, uint256, uint256, address, bytes).selector &&
    f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector
}
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    // In;erest would increase borrow ratio, so we need to assume that no time passes.
    require getLastUpdate(id) == e.block.timestamp;

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    f(e,args);

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    // Check that ratio decreases: assetsBefore/sharesBefore >= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter >= assetsAfter * sharesBefore;
}

// Check that when not accruing interest, repay is decreasing the value of borrow shares.
// Check the case where the market is not repaid fully.
// The other case requires exact math (ie not summarizing mulDivUp and mulDivDown), so it is checked separately in ExactMath.spec
rule repayIncreasesBorrowRatio(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onbehalf, bytes data)
{
    MorphoHarness.Id id = getMarketId(marketParams);
    requireInvariant feeInRange(id);

    // Interest would increase borrow ratio, so we need to assume that no time passes.
    require getLastUpdate(id) == e.block.timestamp;

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    mathint repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onbehalf, data);

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    // Check the case where the market is not repaid fully.
    require repaidAssets < assetsBefore;

    assert assetsAfter == assetsBefore - repaidAssets;
    // Check that ratio decreases: assetsBefore/sharesBefore >= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter >= assetsAfter * sharesBefore;
}
