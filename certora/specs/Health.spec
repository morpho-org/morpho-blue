methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function getLastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function getBorrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getCollateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function isHealthy(MorphoHarness.MarketParams, address user) external returns bool envfree;
    function isAuthorized(address, address user) external returns bool envfree;
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;

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
    require d != 0;
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    require d != 0;
    return require_uint256((x * y) / d);
}

function summaryMin(uint256 a, uint256 b) returns uint256 {
    return a < b ? a : b;
}

// Check that without accruing interest, no interaction can put an healthy account into an unhealthy one.
// This rule times out for liquidate, repay and borrow.
rule stayHealthy(env e, method f, calldataarg data)
filtered {
    f -> !f.isView &&
    f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector &&
    f.selector != sig:repay(MorphoHarness.MarketParams, uint256, uint256, address, bytes).selector &&
    f.selector != sig:borrow(MorphoHarness.MarketParams, uint256, uint256, address, address).selector
}
{
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = getMarketId(marketParams);
    address user;

    // Require that the position is healthy before the interaction.
    require isHealthy(marketParams, user);
    // Require that the LLTV takes coherent values.
    require marketParams.lltv < 10^18;
    require marketParams.lltv > 0;
    // Ensure that no interest is accumulated.
    require getLastUpdate(id) == e.block.timestamp;

    priceChanged = false;
    f(e, data);

    // Safe require because of the invariant sumBorrowSharesCorrect.
    require getBorrowShares(id, user) <= getTotalBorrowShares(id);

    bool stillHealthy = isHealthy(marketParams, user);
    assert !priceChanged => stillHealthy;
}

// Check that users cannot lose collateral by unauthorized parties except in case of an unhealthy position.
rule healthyUserCannotLoseCollateral(env e, method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = getMarketId(marketParams);
    address user;

    // Require that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    // Ensure that no interest is accumulated.
    require getLastUpdate(id) == e.block.timestamp;
    // Require that the user is healthy.
    require isHealthy(marketParams, user);

    mathint collateralBefore = getCollateral(id, user);

    priceChanged = false;
    f(e, data);

    mathint collateralAfter = getCollateral(id, user);

    assert !priceChanged => collateralAfter >= collateralBefore;
}

// Check that users without collateral also have no debt.
// This invariant ensures that bad debt is always accounted.
invariant alwaysCollateralized(MorphoHarness.Id id, address borrower)
    getBorrowShares(id, borrower) != 0 => getCollateral(id, borrower) != 0;
