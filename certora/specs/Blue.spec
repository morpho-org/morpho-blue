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

    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;

    function SafeTransferLib.tmpSafeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, currentContract, to, value);
    function SafeTransferLib.tmpSafeTransferFrom(address token, address from, address to, uint256 value) internal => summarySafeTransferFrom(token, from, to, value);
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

ghost idToBorrowable(MorphoHarness.Id) returns address;
ghost idToCollateral(MorphoHarness.Id) returns address;

hook Sstore supplyShares[KEY MorphoHarness.Id id][KEY address owner] uint256 newShares (uint256 oldShares) STORAGE {
    sumSupplyShares[id] = sumSupplyShares[id] - oldShares + newShares;
}

hook Sstore borrowShares[KEY MorphoHarness.Id id][KEY address owner] uint256 newShares (uint256 oldShares) STORAGE {
    sumBorrowShares[id] = sumBorrowShares[id] - oldShares + newShares;
}

hook Sstore collateral[KEY MorphoHarness.Id id][KEY address owner] uint256 newAmount (uint256 oldAmount) STORAGE {
    sumCollateral[id] = sumCollateral[id] - oldAmount + newAmount;
    expectedAmount[idToCollateral(id)] = expectedAmount[idToCollateral(id)] - oldAmount + newAmount;
}

hook Sstore totalSupply[KEY MorphoHarness.Id id] uint256 newAmount (uint256 oldAmount) STORAGE {
    expectedAmount[idToBorrowable(id)] = expectedAmount[idToBorrowable(id)] - oldAmount + newAmount;
}

hook Sstore totalBorrow[KEY MorphoHarness.Id id] uint256 newAmount (uint256 oldAmount) STORAGE {
    expectedAmount[idToBorrowable(id)] = expectedAmount[idToBorrowable(id)] + oldAmount - newAmount;
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        myBalances[token] = require_uint256(myBalances[token] - amount);
    }
    if (to == currentContract) {
        myBalances[token] = require_uint256(myBalances[token] + amount);
    }
}

definition goodMarket(MorphoHarness.Market market, MorphoHarness.Id id) returns bool =
    (idToBorrowable(id) == market.borrowableToken &&
     idToCollateral(id) == market.collateralToken);

definition VIRTUAL_ASSETS() returns mathint = 1;
definition VIRTUAL_SHARES() returns mathint = 1000000000000000000;
definition MAX_FEE() returns mathint = 250000000000000000;

invariant feeInRange(MorphoHarness.Id id)
    to_mathint(fee(id)) <= MAX_FEE();

invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(totalSupplyShares(id)) == sumSupplyShares[id];
invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(totalBorrowShares(id)) == sumBorrowShares[id];

invariant borrowLessSupply(MorphoHarness.Id id)
    totalBorrow(id) <= totalSupply(id);

invariant isLiquid(address token)
    expectedAmount[token] <= myBalances[token]
{
    preserved supply(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, bytes _d) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
    preserved withdraw(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, address _r) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
    preserved borrow(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, address _r) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
    preserved repay(MorphoHarness.Market market, uint256 _a, uint256 _s, address _o, bytes _d) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
    preserved supplyCollateral(MorphoHarness.Market market, uint256 _a, address _o, bytes _d) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
    preserved withdrawCollateral(MorphoHarness.Market market, uint256 _a, address _o, address _r) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
    preserved liquidate(MorphoHarness.Market market, address _b, uint256 _s, bytes _d) with (env _e) {
        require goodMarket(market, getMarketId(market));
        require _e.msg.sender != currentContract;
    }
}
//invariant liquidOnCollateralToken(MorphoHarness.Market market)
//    myBalances[market.collateralToken] <= collateral(getMarketId(market));

rule supplyRevertZero(MorphoHarness.Market market) {
    env e;
    bytes b;

    supply@withrevert(e, market, 0, 0, e.msg.sender, b);

    assert lastReverted;
}

invariant invOnlyEnabledLltv(MorphoHarness.Market market)
    lastUpdate(getMarketId(market)) != 0 => isLltvEnabled(market.lltv);

invariant invOnlyEnabledIrm(MorphoHarness.Market market)
    lastUpdate(getMarketId(market)) != 0 => isIrmEnabled(market.irm);

/* Check the summaries required by BlueRatioMath.spec */
rule checkSummaryToAssetsUp(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivUp(x, y, d);
    assert result * d >= x * y;
}

rule checkSummaryToAssetsDown(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivDown(x, y, d);
    assert result * d <= x * y;
}
