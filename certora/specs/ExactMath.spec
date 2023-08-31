methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function getVirtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function getFee(MorphoHarness.Id) external returns uint256 envfree;
    function getLastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns uint256 => summaryMulDivUp(a,b,c);
    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => NONDET;
    function _.onMorphoSupply(uint256 assets, bytes data) external => HAVOC_ECF;

    function MAX_FEE() external returns uint256 envfree;
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    return require_uint256((x * y + (d - 1)) / d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    return require_uint256((x * y) / d);
}

rule repayAllResetsBorrowRatio(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onbehalf, bytes data) {
    MorphoHarness.Id id = getMarketId(marketParams);
    require getFee(id) <= MAX_FEE();

    mathint assetsBefore = getVirtualTotalBorrowAssets(id);
    mathint sharesBefore = getVirtualTotalBorrowShares(id);

    require getLastUpdate(id) == e.block.timestamp;

    mathint repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onbehalf, data);

    require repaidAssets >= assetsBefore;

    mathint assetsAfter = getVirtualTotalBorrowAssets(id);
    mathint sharesAfter = getVirtualTotalBorrowShares(id);

    assert assetsAfter == 1;
}

// There should be no profit from supply followed immediately by withdraw.
rule supplyWithdraw() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = getMarketId(marketParams);
    uint256 assets;
    uint256 shares;
    address onbehalf;
    address receiver;
    bytes data;
    env e1;
    env e2;

    // Require interactions to happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Assumption required to cast timestamps to uint128.
    require e1.block.timestamp < 2^128;

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e1, marketParams, assets, shares, onbehalf, data);

    // Hints for the prover.
    assert suppliedAssets * (getVirtualTotalSupplyShares(id) - suppliedShares) >= suppliedShares * (getVirtualTotalSupplyAssets(id) - suppliedAssets);
    assert suppliedAssets * getVirtualTotalSupplyShares(id) >= suppliedShares * getVirtualTotalSupplyAssets(id);

    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    withdrawnAssets, withdrawnShares = withdraw(e2, marketParams, 0, suppliedShares, onbehalf, receiver);

    assert withdrawnShares == suppliedShares;
    assert withdrawnAssets <= suppliedAssets;
}

// There should be no profit from withdraw followed immediately by supply.
rule withdrawSupply() {
    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id id = getMarketId(marketParams);
    uint256 assets;
    uint256 shares;
    address onbehalf;
    address receiver;
    bytes data;
    env e1;
    env e2;

    // Require interactions to happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Assumption required to cast timestamps to uint128.
    require e1.block.timestamp < 2^128;

    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    withdrawnAssets, withdrawnShares = withdraw(e2, marketParams, assets, shares, onbehalf, receiver);

    // Hints for the prover.
    assert withdrawnAssets * (getVirtualTotalSupplyShares(id) + withdrawnShares) <= withdrawnShares * (getVirtualTotalSupplyAssets(id) + withdrawnAssets);
    assert withdrawnAssets * getVirtualTotalSupplyShares(id) <= withdrawnShares * getVirtualTotalSupplyAssets(id);

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e1, marketParams, withdrawnAssets, 0, onbehalf, data);

    assert suppliedAssets == withdrawnAssets && withdrawnShares >= suppliedShares;
}
