methods {
    function owner() external returns address envfree;
    function totalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrow(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isAuthorized(address, address) external returns bool envfree;
    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isLltvEnabled(uint256) external returns bool envfree;
    function isIrmEnabled(address) external returns bool envfree;

    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
    function MAX_FEE() external returns uint256 envfree;
    function WAD() external returns uint256 envfree;
}

definition isCreated(MorphoHarness.Id id) returns bool =
    (lastUpdate(id) != 0);

ghost mapping(MorphoHarness.Id => mathint) sumCollateral
{
    init_state axiom (forall MorphoHarness.Id id. sumCollateral[id] == 0);
}
hook Sstore collateral[KEY MorphoHarness.Id id][KEY address owner] uint256 newAmount (uint256 oldAmount) STORAGE {
    sumCollateral[id] = sumCollateral[id] - oldAmount + newAmount;
}

definition emptyMarket(MorphoHarness.Id id) returns bool =
    totalSupply(id) == 0 &&
    totalSupplyShares(id) == 0 &&
    totalBorrow(id) == 0 &&
    totalBorrowShares(id) == 0 &&
    sumCollateral[id] == 0;

definition exactlyOneZero(uint256 assets, uint256 shares) returns bool =
    (assets == 0 && shares != 0) || (assets != 0 && shares == 0);

// This invariant catches bugs when not checking that the market is created with lastUpdate.
invariant notInitializedEmpty(MorphoHarness.Id id)
    !isCreated(id) => emptyMarket(id);

invariant zeroDoesNotAuthorize(address authorized)
    !isAuthorized(0, authorized)
{
    preserved setAuthorization(address _authorized, bool _newAuthorization) with (env e) {
        require e.msg.sender != 0;
    }
}

rule setOwnerRevertCondition(env e, address newOwner) {
    address oldOwner = owner();
    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

rule enableIrmRevertCondition(env e, address irm) {
    address oldOwner = owner();
    enableIrm@withrevert(e, irm);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

rule enableLltvRevertCondition(env e, uint256 lltv) {
    address oldOwner = owner();
    enableLltv@withrevert(e, lltv);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner || lltv >= WAD();
}

// setFee can also revert if the accrueInterests reverts.
rule setFeeInputValidation(env e, MorphoHarness.Market market, uint256 newFee) {
    address oldOwner = owner();
    MorphoHarness.Id id = getMarketId(market);
    setFee@withrevert(e, market, newFee);
    assert e.msg.value != 0 || e.msg.sender != oldOwner || !isCreated(id) || newFee > MAX_FEE() => lastReverted;
}

rule setFeeRecipientRevertCondition(env e, address recipient) {
    address oldOwner = owner();
    setFeeRecipient@withrevert(e, recipient);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

rule createMarketRevertCondition(env e, MorphoHarness.Market market) {
    MorphoHarness.Id id = getMarketId(market);
    createMarket@withrevert(e, market);
    assert lastReverted <=> e.msg.value != 0 || !isIrmEnabled(market.irm) || !isLltvEnabled(market.lltv) || lastUpdate(id) != 0;
}

rule supplyInputValidation(env e, MorphoHarness.Market market, uint256 assets, uint256 shares, address onBehalf, bytes b) {
    supply@withrevert(e, market, assets, shares, onBehalf, b);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}

rule withdrawInputValidation(env e, MorphoHarness.Market market, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    require e.msg.sender != 0;
    requireInvariant zeroDoesNotAuthorize(e.msg.sender);
    withdraw@withrevert(e, market, assets, shares, onBehalf, receiver);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}

rule borrowInputValidation(env e, MorphoHarness.Market market, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    require e.msg.sender != 0;
    requireInvariant zeroDoesNotAuthorize(e.msg.sender);
    borrow@withrevert(e, market, assets, shares, onBehalf, receiver);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}

rule repayInputValidation(env e, MorphoHarness.Market market, uint256 assets, uint256 shares, address onBehalf, bytes b) {
    repay@withrevert(e, market, assets, shares, onBehalf, b);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}

rule supplyCollateralInputValidation(env e, MorphoHarness.Market market, uint256 assets, address onBehalf, bytes b) {
    supplyCollateral@withrevert(e, market, assets, onBehalf, b);
    assert assets == 0 || onBehalf == 0 => lastReverted;
}

rule withdrawCollateralInputValidation(env e, MorphoHarness.Market market, uint256 assets, address onBehalf, address receiver) {
    require e.msg.sender != 0;
    requireInvariant zeroDoesNotAuthorize(e.msg.sender);
    withdrawCollateral@withrevert(e, market, assets, onBehalf, receiver);
    assert assets == 0 || onBehalf == 0 => lastReverted;
}

rule liquidateInputValidation(env e, MorphoHarness.Market market, address borrower, uint256 seized, bytes b) {
    liquidate@withrevert(e, market, borrower, seized, b);
    assert seized == 0 => lastReverted;
}
