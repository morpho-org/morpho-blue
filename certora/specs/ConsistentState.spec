methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
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

ghost mapping(address => mathint) sumAmount {
    init_state axiom (forall address token. sumAmount[token] == 0);
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
    sumAmount[idToCollateral[id]] = sumAmount[idToCollateral[id]] - oldAmount + newAmount;
}

hook Sstore market[KEY MorphoHarness.Id id].totalSupplyAssets uint128 newAmount (uint128 oldAmount) STORAGE {
    sumAmount[idToBorrowable[id]] = sumAmount[idToBorrowable[id]] - oldAmount + newAmount;
}

hook Sstore market[KEY MorphoHarness.Id id].totalBorrowAssets uint128 newAmount (uint128 oldAmount) STORAGE {
    sumAmount[idToBorrowable[id]] = sumAmount[idToBorrowable[id]] + oldAmount - newAmount;
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

// Check that the fee is always lower than the max fee constant.
invariant feeInRange(MorphoHarness.Id id)
    getFee(id) <= MAX_FEE();

// Check that the accounting of totalSupplyShares is correct.
invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(getTotalSupplyShares(id)) == sumSupplyShares[id];

// Check that the accounting of totalBorrowShares is correct.
invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(getTotalBorrowShares(id)) == sumBorrowShares[id];

// Check that a market only allows borrows up to the total supply.
// This invariant shows that markets are independent, tokens from one market cannot be taken by interacting with another market.
invariant borrowLessSupply(MorphoHarness.Id id)
    getTotalBorrowAssets(id) <= getTotalSupplyAssets(id);

// This invariant is useful in the following rule, to link an id back to a market.
invariant marketInvariant(MorphoHarness.MarketParams marketParams)
    isCreated(getMarketId(marketParams)) =>
    idToBorrowable[getMarketId(marketParams)] == marketParams.borrowableToken &&
    idToCollateral[getMarketId(marketParams)] == marketParams.collateralToken;

// Check that the idle amount on the singleton is greater to the sum amount, that is the sum over all the markets of the total supply plus the total collateral minus the total borrow.
invariant isLiquid(address token)
    sumAmount[token] <= myBalances[token]
{
    preserved supply(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved withdraw(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved borrow(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved repay(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved supplyCollateral(MorphoHarness.MarketParams marketParams, uint256 assets, address onBehalf, bytes data) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved withdrawCollateral(MorphoHarness.MarketParams marketParams, uint256 assets, address onBehalf, address receiver) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
    preserved liquidate(MorphoHarness.MarketParams marketParams, address _b, uint256 shares, uint256 receiver, bytes data) with (env e) {
        requireInvariant marketInvariant(marketParams);
        require e.msg.sender != currentContract;
    }
}

// Check that a market can only exist if its LLTV is enabled.
invariant onlyEnabledLltv(MorphoHarness.MarketParams marketParams)
    isCreated(getMarketId(marketParams)) => isLltvEnabled(marketParams.lltv);

// Check that a market can only exist if its IRM is enabled.
invariant onlyEnabledIrm(MorphoHarness.MarketParams marketParams)
    isCreated(getMarketId(marketParams)) => isIrmEnabled(marketParams.irm);

// Check the pseudo-injectivity of the hashing function id().
rule marketIdUnique() {
    MorphoHarness.MarketParams marketParams1;
    MorphoHarness.MarketParams marketParams2;

    // Require the same arguments.
    require getMarketId(marketParams1) == getMarketId(marketParams2);

    assert marketParams1.borrowableToken == marketParams2.borrowableToken;
    assert marketParams1.collateralToken == marketParams2.collateralToken;
    assert marketParams1.oracle == marketParams2.oracle;
    assert marketParams1.irm == marketParams2.irm;
    assert marketParams1.lltv == marketParams2.lltv;
}

// Check that only the user is able to change who is authorized to manage his position.
rule onlyUserCanAuthorizeWithoutSig(env e, method f, calldataarg data)
filtered {
    f -> !f.isView && f.selector != sig:setAuthorizationWithSig(MorphoHarness.Authorization memory, MorphoHarness.Signature calldata).selector
}
{
    address user;
    address someone;

    // Require a different user to interact with Morpho.
    require user != e.msg.sender;

    bool authorizedBefore = isAuthorized(user, someone);

    f(e, data);

    bool authorizedAfter = isAuthorized(user, someone);

    assert authorizedAfter == authorizedBefore;
}

// Check that only authorized users are able to decrease supply shares of a position.
rule userCannotLoseSupplyShares(env e, method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    address user;

    // Require that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = getSupplyShares(id, user);

    f(e, data);

    mathint sharesAfter = getSupplyShares(id, user);

    assert sharesAfter >= sharesBefore;
}

// Check that only authorized users are able to increase the borrow shares of a position.
rule userCannotGainBorrowShares(env e, method f, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    address user;

    // Require that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = getBorrowShares(id, user);

    f(e, args);

    mathint sharesAfter = getBorrowShares(id, user);

    assert sharesAfter <= sharesBefore;
}

// Check that users cannot lose collateral by unauthorized parties except in case of a liquidation.
rule userCannotLoseCollateralExceptLiquidate(env e, method f, calldataarg args)
filtered {
    f -> !f.isView &&
    f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector
{
    MorphoHarness.Id id;
    address user;

    // Require that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    f(e, args);

    mathint collateralAfter = getCollateral(id, user);

    assert collateralAfter >= collateralBefore;
}

// Check that users cannot lose collateral by unauthorized parties if they have no outstanding debt.
rule userWithoutBorrowCannotLoseCollateral(env e, method f, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    address user;

    // Require that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    // Require that the user has no outstanding debt.
    require getBorrowShares(id, user) == 0;

    mathint collateralBefore = getCollateral(id, user);

    f(e, args);

    mathint collateralAfter = getCollateral(id, user);

    assert collateralAfter >= collateralBefore;
}

// Invariant checking that the last updated time is never greater than the current time.
rule noTimeTravel(method f, env e, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    require getLastUpdate(id) <= e.block.timestamp;
    f(e, args);
    assert getLastUpdate(id) <= e.block.timestamp;
}
