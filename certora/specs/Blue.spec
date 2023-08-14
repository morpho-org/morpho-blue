methods {
    function supply(MorphoHarness.Market, uint256, uint256, address, bytes) external;
    function getVirtualTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function getTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;

    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;
    function isLltvEnabled(uint256) external returns bool envfree;

    function _.borrowRate(MorphoHarness.Market) external => DISPATCHER(true);

    function toId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
    // function _.safeTransfer(address, uint256) internal => DISPATCHER(true);
    // function _.safeTransferFrom(address, address, uint256) internal => DISPATCHER(true);
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

hook Sstore supplyShares[KEY MorphoHarness.Id id][KEY address owner] uint256 newShares (uint256 oldShares) STORAGE {
    sumSupplyShares[id] = sumSupplyShares[id] - oldShares + newShares;
}

hook Sstore borrowShares[KEY MorphoHarness.Id id][KEY address owner] uint256 newShares (uint256 oldShares) STORAGE {
    sumBorrowShares[id] = sumBorrowShares[id] - oldShares + newShares;
}

hook Sstore collateral[KEY MorphoHarness.Id id][KEY address owner] uint256 newAmount (uint256 oldAmount) STORAGE {
    sumCollateral[id] = sumCollateral[id] - oldAmount + newAmount;
}

invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(getTotalSupplyShares(id)) == sumSupplyShares[id];
invariant sumBorrowSharesCorrect(MorphoHarness.Id id)
    to_mathint(getTotalBorrowShares(id)) == sumBorrowShares[id];

rule whatDoesNotIncreaseRatio(MorphoHarness.Id id) {
    mathint assetsBefore = getVirtualTotalSupply(id);
    mathint sharesBefore = getVirtualTotalSupplyShares(id);

    method f;
    env e;
    calldataarg args;

    f(e,args);

    mathint assetsAfter = getVirtualTotalSupply(id);
    mathint sharesAfter = getVirtualTotalSupplyShares(id);

    // check if assetsBefore/shareBefore <= assetsAfter / sharesAfter;
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
}


rule supplyRevertZero(MorphoHarness.Market market) {
    env e;
    bytes b;

    supply@withrevert(e, market, 0, 0, e.msg.sender, b);

    assert lastReverted;
}

rule onlyEnabledLLTV(MorphoHarness.Market market, MorphoHarness.Id id) {
    env e; method f; calldataarg args;

    require id == toId(market);
    require lastUpdate(id) != 0 => isLltvEnabled(market.lltv);

    f(e, args);

    assert lastUpdate(id) != 0 => isLltvEnabled(market.lltv);
}
