methods {
    function getTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function getSupplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getBorrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getCollateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function getFee(MorphoHarness.Id) external returns uint256 envfree;
    function getLastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;

    function isAuthorized(address, address) external returns bool envfree;
    function isLltvEnabled(uint256) external returns bool envfree;
    function isIrmEnabled(address) external returns bool envfree;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => HAVOC_ECF;

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

hook Sstore idToMarketParams[KEY MorphoHarness.Id id].borrowableToken address token STORAGE {
    idToBorrowable[id] = token;
}

hook Sstore idToMarketParams[KEY MorphoHarness.Id id].collateralToken address token STORAGE {
    idToCollateral[id] = token;
}

hook Sstore position[KEY MorphoHarness.Id id][KEY address owner].supplyShares uint256 newShares (uint256 oldShares) STORAGE {
    sumSupplyShares[id] = sumSupplyShares[id] - oldShares + newShares;
}

hook Sstore position[KEY MorphoHarness.Id id][KEY address owner].borrowShares uint128 newShares (uint128 oldShares) STORAGE {
    sumBorrowShares[id] = sumBorrowShares[id] - oldShares + newShares;
}

hook Sstore position[KEY MorphoHarness.Id id][KEY address owner].collateral uint128 newAmount (uint128 oldAmount) STORAGE {
    sumCollateral[id] = sumCollateral[id] - oldAmount + newAmount;
    expectedAmount[idToCollateral[id]] = expectedAmount[idToCollateral[id]] - oldAmount + newAmount;
}

hook Sstore market[KEY MorphoHarness.Id id].totalSupplyAssets uint128 newAmount (uint128 oldAmount) STORAGE {
    expectedAmount[idToBorrowable[id]] = expectedAmount[idToBorrowable[id]] - oldAmount + newAmount;
}

hook Sstore market[KEY MorphoHarness.Id id].totalBorrowAssets uint128 newAmount (uint128 oldAmount) STORAGE {
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
    getLastUpdate(id) != 0;

invariant feeInRange(MorphoHarness.Id id)
    getFee(id) <= MAX_FEE();

invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(getTotalSupplyShares(id)) == sumSupplyShares[id];

invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(getTotalBorrowShares(id)) == sumBorrowShares[id];

invariant borrowLessSupply(MorphoHarness.Id id)
    getTotalBorrowAssets(id) <= getTotalSupplyAssets(id);

invariant marketInvariant(MorphoHarness.MarketParams marketParams)
    isCreated(getMarketId(marketParams)) =>
    idToBorrowable[getMarketId(marketParams)] == marketParams.borrowableToken &&
    idToCollateral[getMarketId(marketParams)] == marketParams.collateralToken;

invariant isLiquid(address token)
    expectedAmount[token] <= myBalances[token]
{
    preserved supply(MorphoHarness.MarketParams marketParams, uint256 _a, uint256 _s, address _o, bytes _d) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved withdraw(MorphoHarness.MarketParams marketParams, uint256 _a, uint256 _s, address _o, address _r) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved borrow(MorphoHarness.MarketParams marketParams, uint256 _a, uint256 _s, address _o, address _r) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved repay(MorphoHarness.MarketParams marketParams, uint256 _a, uint256 _s, address _o, bytes _d) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved supplyCollateral(MorphoHarness.MarketParams marketParams, uint256 _a, address _o, bytes _d) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved withdrawCollateral(MorphoHarness.MarketParams marketParams, uint256 _a, address _o, address _r) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved liquidate(MorphoHarness.MarketParams marketParams, address _b, uint256 _s, uint256 _r, bytes _d) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
}

invariant onlyEnabledLltv(MorphoHarness.MarketParams marketParams)
    isCreated(getMarketId(marketParams)) => isLltvEnabled(marketParams.lltv);

invariant onlyEnabledIrm(MorphoHarness.MarketParams marketParams)
    isCreated(getMarketId(marketParams)) => isIrmEnabled(marketParams.irm);

rule marketIdUnique() {
    MorphoHarness.MarketParams marketParams1;
    MorphoHarness.MarketParams marketParams2;

    require getMarketId(marketParams1) == getMarketId(marketParams2);

    assert marketParams1.borrowableToken == marketParams2.borrowableToken;
    assert marketParams1.collateralToken == marketParams2.collateralToken;
    assert marketParams1.oracle == marketParams2.oracle;
    assert marketParams1.irm == marketParams2.irm;
    assert marketParams1.lltv == marketParams2.lltv;
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
    MorphoHarness.MarketParams marketParams;
    uint256 assets;
    uint256 shares;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    address onbehalf;
    bytes data;
    MorphoHarness.Id id = getMarketId(marketParams);
    env e;

    require e.msg.sender != currentContract;
    require getLastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = getSupplyShares(id, onbehalf);
    mathint balanceBefore = myBalances[marketParams.borrowableToken];

    suppliedAssets, suppliedShares = supply(e, marketParams, assets, shares, onbehalf, data);
    assert assets != 0 => suppliedAssets == assets && shares == 0;
    assert assets == 0 => suppliedShares == shares && shares != 0;

    mathint sharesAfter = getSupplyShares(id, onbehalf);
    mathint balanceAfter = myBalances[marketParams.borrowableToken];
    assert sharesAfter == sharesBefore + suppliedShares;
    assert balanceAfter == balanceBefore + suppliedAssets;
}

rule userCannotLoseSupplyShares(method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.MarketParams marketParams;
    uint256 assets;
    uint256 shares;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    address user;
    MorphoHarness.Id id = getMarketId(marketParams);
    env e;

    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = getSupplyShares(id, user);

    f(e, data);

    mathint sharesAfter = getSupplyShares(id, user);
    assert sharesAfter >= sharesBefore;
}

rule userCannotGainBorrowShares(method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.MarketParams marketParams;
    uint256 assets;
    uint256 shares;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    address user;
    MorphoHarness.Id id = getMarketId(marketParams);
    env e;

    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = getBorrowShares(id, user);

    f(e, data);

    mathint sharesAfter = getBorrowShares(id, user);
    assert sharesAfter <= sharesBefore;
}


rule userWithoutBorrowCannotLoseCollateral(method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.MarketParams marketParams;
    uint256 assets;
    uint256 shares;
    uint256 suppliedAssets;
    uint256 suppliedShares;
    address user;
    MorphoHarness.Id id = getMarketId(marketParams);
    env e;

    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    require getBorrowShares(id, user) == 0;
    mathint collateralBefore = getCollateral(id, user);

    f(e, data);

    mathint collateralAfter = getCollateral(id, user);
    assert getBorrowShares(id, user) == 0;
    assert collateralAfter >= collateralBefore;
}

rule noTimeTravel(method f, env e, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    require getLastUpdate(id) <= e.block.timestamp;
    f(e, data);
    assert getLastUpdate(id) <= e.block.timestamp;
}

rule canWithdrawAll() {
    MorphoHarness.MarketParams marketParams;
    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    address receiver;
    env e;

    MorphoHarness.Id id = getMarketId(marketParams);
    uint256 shares = getSupplyShares(id, e.msg.sender);

    require isCreated(id);
    require e.msg.sender != 0;
    require receiver != 0;
    require e.msg.value == 0;
    require shares > 0;
    require getTotalBorrowAssets(id) == 0;
    require getLastUpdate(id) <= e.block.timestamp;
    require shares < getTotalSupplyShares(id);
    require getTotalSupplyShares(id) < 10^40 && getTotalSupplyAssets(id) < 10^30;

    withdrawnAssets, withdrawnShares = withdraw@withrevert(e, marketParams, 0, shares, e.msg.sender, receiver);

    assert withdrawnShares == shares;
    assert !lastReverted, "Can withdraw all assets if nobody borrows";
}
