methods {
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
}

definition VIRTUAL_ASSETS() returns mathint = 1;
definition VIRTUAL_SHARES() returns mathint = 10^18;
definition MAX_FEE() returns mathint = 10^18 * 25/100;

invariant feeInRange(MorphoHarness.Id id)
    to_mathint(fee(id)) <= MAX_FEE();

/* This is a simple overapproximative summary, stating that it rounds in the right direction.
 * The summary is checked by the specification in BlueRatioMathSummary.spec.
 */
function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require result * d >= x * y;
    return result;
}

/* This is a simple overapproximative summary, stating that it rounds in the right direction.
 * The summary is checked by the specification in BlueRatioMathSummary.spec.
 */
function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require result * d <= x * y;
    return result;
}

rule onlyLiquidateCanDecreaseRatio(method f)
filtered {
    f -> !f.isView && f.selector != sig:liquidate(MorphoHarness.Market, address, uint256, bytes).selector
}
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalSupplyShares(id) + VIRTUAL_SHARES();

    env e;
    calldataarg args;
    f(e,args);

    mathint assetsAfter = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalSupplyShares(id) + VIRTUAL_SHARES();

    // check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter;
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

rule onlyAccrueInterestsCanIncreaseBorrowRatio(method f)
filtered {
    f -> !f.isView
}
{
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalBorrowShares(id) + VIRTUAL_SHARES();

    env e;
    calldataarg args;
    require lastUpdate(id) == e.block.timestamp;
    f(e,args);

    mathint assetsAfter = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalBorrowShares(id) + VIRTUAL_SHARES();

    // check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter;
    assert assetsBefore * sharesAfter >= assetsAfter * sharesBefore;
}
