methods {
    function getVirtualTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrow(MorphoHarness.Id) external returns uint256 envfree;
    function supplyShares(MorphoHarness.Id, address user) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address user) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address user) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;
    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
    function idToMarket(MorphoHarness.Id) external returns (address, address, address, address, uint256) envfree;
    function isAuthorized(address, address) external returns bool envfree;

    function isHealthy(MorphoHarness.Market, address user) external returns bool envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isLltvEnabled(uint256) external returns bool envfree;
    function isIrmEnabled(address) external returns bool envfree;

    function _.borrowRate(MorphoHarness.Market) external => HAVOC_ECF;

    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
    function VIRTUAL_ASSETS() external returns uint256 envfree;
    function VIRTUAL_SHARES() external returns uint256 envfree;
    function MAX_FEE() external returns uint256 envfree;

    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, currentContract, to, value);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => summarySafeTransferFrom(token, from, to, value);
}

ghost mapping(MorphoHarness.Id => mathint) sumSupplyShares {
    init_state axiom (forall MorphoHarness.Id id. sumSupplyShares[id] == 0);
}

ghost mapping(MorphoHarness.Id => mathint) sumBorrowShares {
    init_state axiom (forall MorphoHarness.Id id. sumBorrowShares[id] == 0);
}

ghost mapping(MorphoHarness.Id => mathint) sumCollateral {
    init_state axiom (forall MorphoHarness.Id id. sumCollateral[id] == 0);
}

ghost mapping(address => mathint) myBalances {
    init_state axiom (forall address token. myBalances[token] == 0);
}

ghost mapping(address => mathint) expectedAmount {
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

definition isCreated(MorphoHarness.Id id) returns bool =
    (lastUpdate(id) != 0);

invariant feeInRange(MorphoHarness.Id id)
    fee(id) <= MAX_FEE();

invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(totalSupplyShares(id)) == sumSupplyShares[id];

invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(totalBorrowShares(id)) == sumBorrowShares[id];

invariant borrowLessSupply(MorphoHarness.Id id)
    totalBorrow(id) <= totalSupply(id);

invariant marketInvariant(MorphoHarness.Market market)
    isCreated(getMarketId(market)) =>
    idToBorrowable[getMarketId(market)] == market.borrowableToken &&
    idToCollateral[getMarketId(market)] == market.collateralToken;

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

invariant onlyEnabledLltv(MorphoHarness.Market market)
    isCreated(getMarketId(market)) => isLltvEnabled(market.lltv);

invariant onlyEnabledIrm(MorphoHarness.Market market)
    isCreated(getMarketId(market)) => isIrmEnabled(market.irm);

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

rule onlyUserCanAuthorizeWithoutSig(method f, calldataarg data)
filtered {
    f -> !f.isView && f.selector != sig:setAuthorizationWithSig(MorphoHarness.Authorization memory, MorphoHarness.Signature calldata).selector
}
{
    address user;
    address someone;
    env e;

    require user != e.msg.sender;
    bool authorizedBefore = isAuthorized(user, someone);

    f(e, data);

    assert isAuthorized(user, someone) == authorizedBefore;
}

rule supplyMovesTokensAndIncreasesShares() {
    MorphoHarness.Market market;
    uint256 assets;
    uint256 shares;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    address onbehalf;
    bytes data;
    MorphoHarness.Id id = getMarketId(market);
    env e;

    require e.msg.sender != currentContract;
    require lastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = supplyShares(id, onbehalf);
    mathint balanceBefore = myBalances[market.borrowableToken];

    suppliedAssets, suppliedShares = supply(e, market, assets, shares, onbehalf, data);
    assert assets != 0 => suppliedAssets == assets && shares == 0;
    assert assets == 0 => suppliedShares == shares && shares != 0;

    mathint sharesAfter = supplyShares(id, onbehalf);
    mathint balanceAfter = myBalances[market.borrowableToken];
    assert sharesAfter == sharesBefore + suppliedShares;
    assert balanceAfter == balanceBefore + suppliedAssets;
}

rule userCannotLoseSupplyShares(method f, calldataarg data)
filtered { f -> !f.isView }
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

    mathint sharesBefore = supplyShares(id, user);

    f(e, data);

    mathint sharesAfter = supplyShares(id, user);
    assert sharesAfter >= sharesBefore;
}

rule userCannotGainBorrowShares(method f, calldataarg data)
filtered { f -> !f.isView }
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

    mathint sharesBefore = borrowShares(id, user);

    f(e, data);

    mathint sharesAfter = borrowShares(id, user);
    assert sharesAfter <= sharesBefore;
}


rule userWithoutBorrowCannotLoseCollateral(method f, calldataarg data)
filtered { f -> !f.isView }
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
    require borrowShares(id, user) == 0;
    mathint collateralBefore = collateral(id, user);

    f(e, data);

    mathint collateralAfter = collateral(id, user);
    assert borrowShares(id, user) == 0;
    assert collateralAfter >= collateralBefore;
}

rule noTimeTravel(method f, env e, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    require lastUpdate(id) <= e.block.timestamp;
    f(e, data);
    assert lastUpdate(id) <= e.block.timestamp;
}

rule canWithdrawAll() {
    MorphoHarness.Market market;
    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    address receiver;
    env e;

    MorphoHarness.Id id = getMarketId(market);
    uint256 shares = supplyShares(id, e.msg.sender);

    require isCreated(id);
    require e.msg.sender != 0;
    require receiver != 0;
    require e.msg.value == 0;
    require shares > 0;
    require totalBorrow(id) == 0;
    require lastUpdate(id) <= e.block.timestamp;
    require shares < totalSupplyShares(id);
    require totalSupplyShares(id) < 10^40 && totalSupply(id) < 10^30;

    withdrawnAssets, withdrawnShares = withdraw@withrevert(e, market, 0, shares, e.msg.sender, receiver);

    assert withdrawnShares == shares;
    assert !lastReverted, "Can withdraw all assets if nobody borrows";
}
