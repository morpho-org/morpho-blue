methods {
    function supply(MorphoHarness.Market, uint256, uint256, address, bytes) external;
    function getVirtualTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrow(MorphoHarness.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function fee(MorphoHarness.Id) external returns uint256 envfree;

    function _.borrowRate(MorphoHarness.Market) external => HAVOC_ECF;

    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function _.safeTransfer(address, uint256) internal => DISPATCHER(true);
    function _.safeTransferFrom(address, address, uint256) internal => DISPATCHER(true);
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

rule supplyRevertZero(MorphoHarness.Market market) {
    env e;
    bytes b;

    supply@withrevert(e, market, 0, 0, e.msg.sender, b);

    assert lastReverted;
}

/* Check the summaries required by BlueRatioMath.spec */
rule checkSummaryToAssetsUp(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivUp(x, y, d);
    assert result * d >= x * y;
}

rule checkSummaryToAssetsDown(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivDown(x, y, d);
    assert result * d <= x * y;
}
