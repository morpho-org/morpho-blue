// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function owner() external returns address envfree;
    function feeRecipient() external returns address envfree;
    function totalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isIrmEnabled(address) external returns bool envfree;
    function isLltvEnabled(uint256) external returns bool envfree;
    function isAuthorized(address, address) external returns bool envfree;
    function nonce(address) external returns uint256 envfree;

    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;

    function maxFee() external returns uint256 envfree;
    function wad() external returns uint256 envfree;
}

definition isCreated(MorphoHarness.Id id) returns bool =
    (lastUpdate(id) != 0);

ghost mapping(MorphoHarness.Id => mathint) sumCollateral
{
    init_state axiom (forall MorphoHarness.Id id. sumCollateral[id] == 0);
}
hook Sstore position[KEY MorphoHarness.Id id][KEY address owner].collateral uint128 newAmount (uint128 oldAmount) STORAGE {
    sumCollateral[id] = sumCollateral[id] - oldAmount + newAmount;
}

definition emptyMarket(MorphoHarness.Id id) returns bool =
    totalSupplyAssets(id) == 0 &&
    totalSupplyShares(id) == 0 &&
    totalBorrowAssets(id) == 0 &&
    totalBorrowShares(id) == 0 &&
    sumCollateral[id] == 0;

definition exactlyOneZero(uint256 assets, uint256 shares) returns bool =
    (assets == 0 && shares != 0) || (assets != 0 && shares == 0);

// This invariant catches bugs when not checking that the market is created with lastUpdate.
invariant notCreatedIsEmpty(MorphoHarness.Id id)
    !isCreated(id) => emptyMarket(id)
{
    preserved with (env e) {
        // Safe require because timestamps cannot realistically be that large.
        require e.block.timestamp < 2^128;
    }
}

// Useful to ensure that authorized parties are not the zero address and so we can omit the sanity check in this case.
invariant zeroDoesNotAuthorize(address authorized)
    !isAuthorized(0, authorized)
{
    preserved setAuthorization(address _authorized, bool _newAuthorization) with (env e) {
        // Safe require because no one controls the zero address.
        require e.msg.sender != 0;
    }
}

// Check the revert condition for the setOwner function.
rule setOwnerRevertCondition(env e, address newOwner) {
    address oldOwner = owner();
    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner || newOwner == oldOwner;
}

// Check the revert condition for the setOwner function.
rule enableIrmRevertCondition(env e, address irm) {
    address oldOwner = owner();
    bool oldIsIrmEnabled = isIrmEnabled(irm);
    enableIrm@withrevert(e, irm);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner || oldIsIrmEnabled;
}

// Check the revert condition for the enableLltv function.
rule enableLltvRevertCondition(env e, uint256 lltv) {
    address oldOwner = owner();
    bool oldIsLltvEnabled = isLltvEnabled(lltv);
    enableLltv@withrevert(e, lltv);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner || lltv >= wad() || oldIsLltvEnabled;
}

// Check that setFee reverts when its inputs are not validated.
// setFee can also revert if the accrueInterest reverts.
rule setFeeInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 newFee) {
    MorphoHarness.Id id = libId(marketParams);
    address oldOwner = owner();
    bool wasCreated = isCreated(id);
    setFee@withrevert(e, marketParams, newFee);
    bool hasReverted = lastReverted;
    assert e.msg.value != 0 || e.msg.sender != oldOwner || !wasCreated || newFee > maxFee() => hasReverted;
}

// Check the revert condition for the setFeeRecipient function.
rule setFeeRecipientRevertCondition(env e, address newFeeRecipient) {
    address oldOwner = owner();
    address oldFeeRecipient = feeRecipient();
    setFeeRecipient@withrevert(e, newFeeRecipient);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner || newFeeRecipient == oldFeeRecipient;
}

// Check that createMarket reverts when its input are not validated.
rule createMarketInputValidation(env e, MorphoHarness.MarketParams marketParams) {
    MorphoHarness.Id id = libId(marketParams);
    bool irmEnabled = isIrmEnabled(marketParams.irm);
    bool lltvEnabled = isLltvEnabled(marketParams.lltv);
    bool wasCreated = isCreated(id);
    createMarket@withrevert(e, marketParams);
    assert e.msg.value != 0 || !irmEnabled || !lltvEnabled || wasCreated => lastReverted;
}

// Check that supply reverts when its input are not validated.
rule supplyInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    supply@withrevert(e, marketParams, assets, shares, onBehalf, data);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}

// Check that withdraw reverts when its inputs are not validated.
rule withdrawInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    // Safe require because no one controls the zero address.
    require e.msg.sender != 0;
    requireInvariant zeroDoesNotAuthorize(e.msg.sender);
    withdraw@withrevert(e, marketParams, assets, shares, onBehalf, receiver);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 || receiver == 0 => lastReverted;
}

// Check that borrow reverts when its inputs are not validated.
rule borrowInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    // Safe require because no one controls the zero address.
    require e.msg.sender != 0;
    requireInvariant zeroDoesNotAuthorize(e.msg.sender);
    borrow@withrevert(e, marketParams, assets, shares, onBehalf, receiver);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0  || receiver == 0 => lastReverted;
}

// Check that repay reverts when its inputs are not validated.
rule repayInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    repay@withrevert(e, marketParams, assets, shares, onBehalf, data);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}

// Check that supplyCollateral reverts when its inputs are not validated.
rule supplyCollateralInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, address onBehalf, bytes data) {
    supplyCollateral@withrevert(e, marketParams, assets, onBehalf, data);
    assert assets == 0 || onBehalf == 0 => lastReverted;
}

// Check that withdrawCollateral reverts when its inputs are not validated.
rule withdrawCollateralInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, address onBehalf, address receiver) {
    // Safe require because no one controls the zero address.
    require e.msg.sender != 0;
    requireInvariant zeroDoesNotAuthorize(e.msg.sender);
    withdrawCollateral@withrevert(e, marketParams, assets, onBehalf, receiver);
    assert assets == 0 || onBehalf == 0 || receiver == 0 => lastReverted;
}

// Check that liquidate reverts when its inputs are not validated.
rule liquidateInputValidation(env e, MorphoHarness.MarketParams marketParams, address borrower, uint256 seizedAssets, uint256 repaidShares, bytes data) {
    liquidate@withrevert(e, marketParams, borrower, seizedAssets, repaidShares, data);
    assert !exactlyOneZero(seizedAssets, repaidShares) => lastReverted;
}

// Check that setAuthorizationWithSig reverts when its inputs are not validated.
rule setAuthorizationWithSigInputValidation(env e, MorphoHarness.Authorization authorization, MorphoHarness.Signature signature) {
    uint256 nonceBefore = nonce(authorization.authorizer);
    setAuthorizationWithSig@withrevert(e, authorization, signature);
    assert e.block.timestamp > authorization.deadline || authorization.nonce != nonceBefore => lastReverted;
}

// Check that accrueInterest reverts when its inputs are not validated.
rule accrueInterestInputValidation(env e, MorphoHarness.MarketParams marketParams) {
    bool wasCreated = isCreated(libId(marketParams));
    accrueInterest@withrevert(e, marketParams);
    assert !wasCreated => lastReverted;
}
