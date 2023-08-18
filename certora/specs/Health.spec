methods {
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function isHealthy(MorphoHarness.Market, address user) external returns bool envfree;
    function isAuthorized(address, address user) external returns bool envfree;
    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
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
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    return require_uint256((x * y) / d);
}

function summaryMin(uint256 a, uint256 b) returns uint256 {
    return a < b ? a : b;
}

rule stayHealthy(method f, env e, calldataarg data)
filtered {
    f -> !f.isView
}
{
    MorphoHarness.Market market;
    MorphoHarness.Id id = getMarketId(market);
    address user;

    require isHealthy(market, user);
    require market.lltv < 10^18;
    require market.lltv > 0;
    require lastUpdate(id) == e.block.timestamp;
    priceChanged = false;

    f(e, data);

    bool stillHealthy = isHealthy(market, user);
    assert !priceChanged => stillHealthy;
}

rule healthyUserCannotLoseCollateral(method f, calldataarg data)
filtered {
    f -> !f.isView
}
{
    MorphoHarness.Market market;
    uint256 assets;
    uint256 shares;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    address user;
    MorphoHarness.Id id = getMarketId(market);
    env e;

    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    require lastUpdate(id) == e.block.timestamp;
    require isHealthy(market, user);
    mathint collateralBefore = collateral(id, user);
    priceChanged = false;

    f(e, data);

    require !priceChanged;
    mathint collateralAfter = collateral(id, user);
    assert collateralAfter >= collateralBefore;
}