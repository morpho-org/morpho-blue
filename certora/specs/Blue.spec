methods {
    function supply(MorphoHarness.Market, uint256, uint256, address, bytes) external;
    function getVirtualTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrow(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;
    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
    function idToMarket(MorphoHarness.Id) external returns (address, address, address, address, uint256) envfree;
    function isAuthorized(address, address) external returns bool envfree;

    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isLltvEnabled(uint256) external returns bool envfree;
    function isIrmEnabled(address) external returns bool envfree;

    function _.borrowRate(MorphoHarness.Market) external => HAVOC_ECF;

    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;

    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, currentContract, to, value);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => summarySafeTransferFrom(token, from, to, value);
}

ghost mapping(MorphoHarness.Id => mathint) sumSupplyShares
{
    init_state axiom (forall MorphoHarness.Id id. sumSupplyShares[id] == 0);
}
ghost mapping(MorphoHarness.Id => mathint) sumBorrowShares
{
    init_state axiom (forall MorphoHarness.Id id. sumBorrowShares[id] == 0);
}
ghost mapping(MorphoHarness.Id => mathint) sumCollateral
{
    init_state axiom (forall MorphoHarness.Id id. sumCollateral[id] == 0);
}
ghost mapping(address => mathint) myBalances
{
    init_state axiom (forall address token. myBalances[token] == 0);
}
ghost mapping(address => mathint) expectedAmount
{
    init_state axiom (forall address token. expectedAmount[token] == 0);
}

ghost mapping(MorphoHarness.Id => address) idToBorrowable;
ghost mapping(MorphoHarness.Id => address) idToCollateral;

hook Sstore idToMarket[KEY MorphoHarness.Id id].borrowableToken address token STORAGE {
    idToBorrowable[id] = token;
}
hook Sstore idToMarket[KEY MorphoHarness.Id id].collateralToken address token STORAGE {
    idToCollateral[id] = token;
}

hook Sstore supplyShares[KEY MorphoHarness.Id id][KEY address owner] uint256 newShares (uint256 oldShares) STORAGE {
    sumSupplyShares[id] = sumSupplyShares[id] - oldShares + newShares;
}

hook Sstore borrowShares[KEY MorphoHarness.Id id][KEY address owner] uint256 newShares (uint256 oldShares) STORAGE {
    sumBorrowShares[id] = sumBorrowShares[id] - oldShares + newShares;
}

hook Sstore collateral[KEY MorphoHarness.Id id][KEY address owner] uint256 newAmount (uint256 oldAmount) STORAGE {
    sumCollateral[id] = sumCollateral[id] - oldAmount + newAmount;
    expectedAmount[idToCollateral[id]] = expectedAmount[idToCollateral[id]] - oldAmount + newAmount;
}

hook Sstore totalSupply[KEY MorphoHarness.Id id] uint256 newAmount (uint256 oldAmount) STORAGE {
    expectedAmount[idToBorrowable[id]] = expectedAmount[idToBorrowable[id]] - oldAmount + newAmount;
}

hook Sstore totalBorrow[KEY MorphoHarness.Id id] uint256 newAmount (uint256 oldAmount) STORAGE {
    expectedAmount[idToBorrowable[id]] = expectedAmount[idToBorrowable[id]] + oldAmount - newAmount;
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        myBalances[token] = require_uint256(myBalances[token] - amount);
    }
    if (to == currentContract) {
        myBalances[token] = require_uint256(myBalances[token] + amount);
    }
}

definition VIRTUAL_ASSETS() returns mathint = 1;
definition VIRTUAL_SHARES() returns mathint = 10^18;
definition MAX_FEE() returns mathint = 10^18 * 25/100;
definition isInitialized(MorphoHarness.Id id) returns bool =
    (lastUpdate(id) != 0);


invariant feeInRange(MorphoHarness.Id id)
    to_mathint(fee(id)) <= MAX_FEE();

invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(totalSupplyShares(id)) == sumSupplyShares[id];
invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(totalBorrowShares(id)) == sumBorrowShares[id];

invariant borrowLessSupply(MorphoHarness.Id id)
    totalBorrow(id) <= totalSupply(id);

invariant marketInvariant(MorphoHarness.Market market)
    isInitialized(getMarketId(market)) =>
    idToBorrowable[getMarketId(market)] == market.borrowableToken
    && idToCollateral[getMarketId(market)] == market.collateralToken;

invariant isLiquid(address token)
    expectedAmount[token] <= myBalances[token]
{
    preserved supply(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, bytes _d) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
    preserved withdraw(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, address _r) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
    preserved borrow(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, address _r) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
    preserved repay(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, bytes _d) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
    preserved supplyCollateral(MorphoHarness.Market market, uint256 _a, address _o, bytes _d) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
    preserved withdrawCollateral(MorphoHarness.Market market, uint256 _a, address _o, address _r) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
    preserved liquidate(MorphoHarness.Market market, address _b, uint256 _s, bytes _d) with (env e) {
        requireInvariant marketInvariant(market);
        require e.msg.sender != currentContract;
    }
}

rule supplyRevertZero(MorphoHarness.Market market) {
    env e;
    bytes b;

    supply@withrevert(e, market, 0, 0, e.msg.sender, b);

    assert lastReverted;
}

invariant onlyEnabledLltv(MorphoHarness.Market market)
    isInitialized(getMarketId(market)) => isLltvEnabled(market.lltv);

invariant onlyEnabledIrm(MorphoHarness.Market market)
    isInitialized(getMarketId(market)) => isIrmEnabled(market.irm);

rule marketIdUnique() {
    MorphoHarness.Market market1;
    MorphoHarness.Market market2;

    require getMarketId(market1) == getMarketId(market2);

    assert market1.borrowableToken == market2.borrowableToken;
    assert market1.collateralToken == market2.collateralToken;
    assert market1.oracle == market2.oracle;
    assert market1.irm == market2.irm;
    assert market1.lltv == market2.lltv;
}
