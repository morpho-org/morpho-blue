methods {
    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
    function totalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrow(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivUp(a,b,c);
    function MathLib.wTaylorCompounded(uint256, uint256) internal returns uint256 => NONDET;

    function _.borrowRate(MorphoHarness.Market) external => HAVOC_ECF;

    function VIRTUAL_ASSETS() external returns uint256 envfree;
    function VIRTUAL_SHARES() external returns uint256 envfree;
    function MAX_FEE() external returns uint256 envfree;
}

invariant feeInRange(MorphoHarness.Id id)
    to_mathint(fee(id)) <= MAX_FEE();

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
    MorphoHarness.Market market;
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalSupplyShares(id) + VIRTUAL_SHARES();

    // The check is done for every market, not just for id.
    env e;
    accrueInterests(e, market);

    mathint assetsAfter = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalSupplyShares(id) + VIRTUAL_SHARES();

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

rule accrueInterestsIncreasesBorrowRatio() {
    MorphoHarness.Market market;
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalBorrowShares(id) + VIRTUAL_SHARES();

    // The check is done for every market, not just for id.
    env e;
    accrueInterests(e, market);

    mathint assetsAfter = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalBorrowShares(id) + VIRTUAL_SHARES();

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}


rule onlyLiquidateCanDecreaseSupplyRatio(env e, method f, calldataarg args)
filtered {
    f -> !f.isView && f.selector != sig:liquidate(MorphoHarness.Market, address, uint256, bytes).selector
}
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalSupplyShares(id) + VIRTUAL_SHARES();

    // Interest is checked separately by the rules above.
    // Here we assume interest has already been accumulated for this block.
    require lastUpdate(id) == e.block.timestamp;

    f(e,args);

    mathint assetsAfter = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalSupplyShares(id) + VIRTUAL_SHARES();

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

rule onlyAccrueInterestsCanIncreaseBorrowRatio(env e, method f, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalBorrowShares(id) + VIRTUAL_SHARES();

    // Interest would increase borrow ratio, so we need to assume no time passes.
    require lastUpdate(id) == e.block.timestamp;

    f(e,args);

    mathint assetsAfter = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalBorrowShares(id) + VIRTUAL_SHARES();

    // Check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter
    assert assetsBefore * sharesAfter >= assetsAfter * sharesBefore;
}
