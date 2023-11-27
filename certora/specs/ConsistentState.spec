// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function supplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function totalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isIrmEnabled(address) external returns bool envfree;
    function isLltvEnabled(uint256) external returns bool envfree;
    function isAuthorized(address, address) external returns bool envfree;

    function maxFee() external returns uint256 envfree;
    function wad() external returns uint256 envfree;
    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => HAVOC_ECF;

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

ghost mapping(address => mathint) balance {
    init_state axiom (forall address token. balance[token] == 0);
}

ghost mapping(address => mathint) idleAmount {
    init_state axiom (forall address token. idleAmount[token] == 0);
}

ghost mapping(MorphoHarness.Id => address) idToBorrowable;

ghost mapping(MorphoHarness.Id => address) idToCollateral;

hook Sstore idToMarketParams[KEY MorphoHarness.Id id].loanToken address token STORAGE {
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
    idleAmount[idToCollateral[id]] = idleAmount[idToCollateral[id]] - oldAmount + newAmount;
}

hook Sstore market[KEY MorphoHarness.Id id].totalSupplyAssets uint128 newAmount (uint128 oldAmount) STORAGE {
    idleAmount[idToBorrowable[id]] = idleAmount[idToBorrowable[id]] - oldAmount + newAmount;
}

hook Sstore market[KEY MorphoHarness.Id id].totalBorrowAssets uint128 newAmount (uint128 oldAmount) STORAGE {
    idleAmount[idToBorrowable[id]] = idleAmount[idToBorrowable[id]] + oldAmount - newAmount;
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        // Safe require because the reference implementation would revert.
        balance[token] = require_uint256(balance[token] - amount);
    }
    if (to == currentContract) {
        // Safe require because the reference implementation would revert.
        balance[token] = require_uint256(balance[token] + amount);
    }
}

definition isCreated(MorphoHarness.Id id) returns bool =
    lastUpdate(id) != 0;

// Check that the fee is always lower than the max fee constant.
invariant feeInRange(MorphoHarness.Id id)
    fee(id) <= maxFee();

// Check that the accounting of totalSupplyShares is correct.
invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(totalSupplyShares(id)) == sumSupplyShares[id];

// Check that the accounting of totalBorrowShares is correct.
invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(totalBorrowShares(id)) == sumBorrowShares[id];

// Check that a market only allows borrows up to the total supply.
// This invariant shows that markets are independent, tokens from one market cannot be taken by interacting with another market.
invariant borrowLessThanSupply(MorphoHarness.Id id)
    totalBorrowAssets(id) <= totalSupplyAssets(id);

// This invariant is useful in the following rule, to link an id back to a market.
invariant marketInvariant(MorphoHarness.MarketParams marketParams)
    isCreated(libId(marketParams)) =>
    idToBorrowable[libId(marketParams)] == marketParams.loanToken &&
    idToCollateral[libId(marketParams)] == marketParams.collateralToken;

// Check that the idle amount on the singleton is greater to the sum amount, that is the sum over all the markets of the total supply plus the total collateral minus the total borrow.
invariant idleAmountLessThanBalance(address token)
    idleAmount[token] <= balance[token]
{
    // Safe requires on the sender because the contract cannot call the function itself.
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
    isCreated(libId(marketParams)) => isLltvEnabled(marketParams.lltv);

invariant lltvSmallerThanWad(uint256 lltv)
    isLltvEnabled(lltv) => lltv < wad();

// Check that a market can only exist if its IRM is enabled.
invariant onlyEnabledIrm(MorphoHarness.MarketParams marketParams)
    isCreated(libId(marketParams)) => isIrmEnabled(marketParams.irm);

// Check the pseudo-injectivity of the hashing function id().
rule libIdUnique() {
    MorphoHarness.MarketParams marketParams1;
    MorphoHarness.MarketParams marketParams2;

    // Assume that arguments are the same.
    require libId(marketParams1) == libId(marketParams2);

    assert marketParams1.loanToken == marketParams2.loanToken;
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

    // Assume that it is another user that is interacting with Morpho.
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

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = supplyShares(id, user);

    f(e, data);

    mathint sharesAfter = supplyShares(id, user);

    assert sharesAfter >= sharesBefore;
}

// Check that only authorized users are able to increase the borrow shares of a position.
rule userCannotGainBorrowShares(env e, method f, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    address user;

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = borrowShares(id, user);

    f(e, args);

    mathint sharesAfter = borrowShares(id, user);

    assert sharesAfter <= sharesBefore;
}

// Check that users cannot lose collateral by unauthorized parties except in case of a liquidation.
rule userCannotLoseCollateralExceptLiquidate(env e, method f, calldataarg args)
filtered {
    f -> !f.isView &&
    f.selector != sig:liquidate(MorphoHarness.MarketParams, address, uint256, uint256, bytes).selector
}
{
    MorphoHarness.Id id;
    address user;

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint collateralBefore = collateral(id, user);

    f(e, args);

    mathint collateralAfter = collateral(id, user);

    assert collateralAfter >= collateralBefore;
}

// Check that users cannot lose collateral by unauthorized parties if they have no outstanding debt.
rule userWithoutBorrowCannotLoseCollateral(env e, method f, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    address user;

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;
    // Assume that the user has no outstanding debt.
    require borrowShares(id, user) == 0;

    mathint collateralBefore = collateral(id, user);

    f(e, args);

    mathint collateralAfter = collateral(id, user);

    assert collateralAfter >= collateralBefore;
}

// Invariant checking that the last updated time is never greater than the current time.
rule noTimeTravel(method f, env e, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    // Assume the property before the interaction.
    require lastUpdate(id) <= e.block.timestamp;
    f(e, args);
    assert lastUpdate(id) <= e.block.timestamp;
}
