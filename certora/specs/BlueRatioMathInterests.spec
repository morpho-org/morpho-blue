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

rule checkAccrueInterestsSummary()
{
    MorphoHarness.Market market;
    MorphoHarness.Id id = getMarketId(market);
    MorphoHarness.Id otherId;

    requireInvariant feeInRange(id);
    require otherId != id;

    uint256 oldSupply = totalSupply(id);
    uint256 oldSupplyShares = totalSupplyShares(id);
    uint256 oldBorrow = totalBorrow(id);

    uint256 oldSupplyOther = totalSupply(otherId);
    uint256 oldSupplySharesOther = totalSupplyShares(otherId);
    uint256 oldBorrowOther = totalBorrow(otherId);

    env e;
    accrueInterests(e, market);

    uint256 newSupply = totalSupply(id);
    uint256 newSupplyShares = totalSupplyShares(id);
    uint256 newBorrow = totalBorrow(id);

    uint256 newSupplyOther = totalSupply(otherId);
    uint256 newSupplySharesOther = totalSupplyShares(otherId);
    uint256 newBorrowOther = totalBorrow(otherId);

    assert oldSupplyOther == newSupplyOther;
    assert oldSupplySharesOther == newSupplySharesOther;
    assert oldBorrowOther == newBorrowOther;

    mathint interests = newSupply - oldSupply;

    assert interests >= 0;
    assert to_mathint(newBorrow) == oldBorrow + interests;
    assert to_mathint(newSupply) == oldSupply + interests;
    assert newSupplyShares >= oldSupplyShares;

    assert (VIRTUAL_ASSETS() + oldSupply) * (VIRTUAL_SHARES() + newSupplyShares) <=
            (VIRTUAL_ASSETS() + newSupply) * (VIRTUAL_SHARES() + oldSupplyShares);
}

rule accrueInterestsIncreasesRatio()
{
    MorphoHarness.Market market;
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalSupplyShares(id) + VIRTUAL_SHARES();

    // we actually check it for every market, not just for id.
    env e;
    accrueInterests(e, market);

    mathint assetsAfter = totalSupply(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalSupplyShares(id) + VIRTUAL_SHARES();

    // check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter;
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

rule accrueInterestsIncreasesBorrowRatio()
{
    MorphoHarness.Market market;
    MorphoHarness.Id id;
    requireInvariant feeInRange(id);

    mathint assetsBefore = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesBefore = totalBorrowShares(id) + VIRTUAL_SHARES();

    // we actually check it for every market, not just for id.
    env e;
    accrueInterests(e, market);

    mathint assetsAfter = totalBorrow(id) + VIRTUAL_ASSETS();
    mathint sharesAfter = totalBorrowShares(id) + VIRTUAL_SHARES();

    // check if ratio increases: assetsBefore/sharesBefore <= assetsAfter / sharesAfter;
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}

