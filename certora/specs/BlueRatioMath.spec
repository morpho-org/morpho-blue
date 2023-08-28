methods {
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
// The summary is checked by the specification in BlueRatioMathSummary.spec.
function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require result * d >= x * y;
    return result;
}

// This is a simple overapproximative summary, stating that it rounds in the right direction.
// The summary is checked by the specification in BlueRatioMathSummary.spec.
function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require result * d <= x * y;
    return result;
}

rule accrueInterestsIncreasesSupplyRatio() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalSupplyAssets(id);
    mathint sharesBefore = getVirtualTotalSupplyShares(id);

    // The check is done for every market, not just for id.
    env e;
    accrueInterest(e, marketParams);

    mathint assetsAfter = getVirtualTotalSupplyAssets(id);
    mathint sharesAfter = getVirtualTotalSupplyShares(id);

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

rule accrueInterestsIncreasesBorrowRatio() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    // The check is done for every marketParams, not just for id.
    env e;
    accrueInterest(e, marketParams);

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}


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

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

rule onlyAccrueInterestsCanIncreaseBorrowRatio(env e, method f, calldataarg args)
filtered {
    f -> !f.isView && f.selector != sig:repay(MorphoHarness.MarketParams, uint256, uint256, address, bytes).selector
}
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    // Interest would increase borrow ratio, so we need to assume no time passes.
    require getLastUpdate(id) == e.block.timestamp;

    f(e,args);

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter >= assetsAfter * sharesBefore;
}

rule repayIncreasesBorrowRatio(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onbehalf, bytes data)
{
    MorphoHarness.Id id = getMarketId(marketParams);
    requireInvariant feeInRange(id);

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    require getLastUpdate(id) == e.block.timestamp;

    mathint repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onbehalf, data);

    require repaidAssets < assetsBefore;

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    assert assetsAfter == assetsBefore - repaidAssets;
    assert assetsBefore * sharesAfter >= assetsAfter * sharesBefore;
}
