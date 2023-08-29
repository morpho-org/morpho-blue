methods {
    function getSupplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getBorrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getCollateral(MorphoHarness.Id, address) external returns uint256 envfree;
    function getVirtualTotalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowAssets(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;

    function getLastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

rule withdrawLiquidity(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    env e;
    MorphoHarness.Id id = getMarketId(marketParams);

    require getLastUpdate(id) == e.block.timestamp;

    uint256 initialShares = getSupplyShares(id, onBehalf);
    uint256 initialTotalSupply = getVirtualTotalSupplyAssets(id);
    uint256 initialTotalSupplyShares = getVirtualTotalSupplyShares(id);
    uint256 owedAssets = mathLibMulDivDown(initialShares, initialTotalSupply, initialTotalSupplyShares);

    uint256 withdrawnAssets;
    withdrawnAssets, _ = withdraw(e, marketParams, assets, shares, onBehalf, receiver);

    assert withdrawnAssets <= owedAssets;
}

rule withdrawCollateralLiquidity(MorphoHarness.MarketParams marketParams, uint256 assets, address onBehalf, address receiver) {
    env e;
    MorphoHarness.Id id = getMarketId(marketParams);

    uint256 initialCollateral = getCollateral(id, onBehalf);

    withdrawCollateral(e, marketParams, assets, onBehalf, receiver);

    assert assets <= initialCollateral;
}

rule repayLiquidity(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    env e;
    MorphoHarness.Id id = getMarketId(marketParams);

    require getLastUpdate(id) == e.block.timestamp;

    uint256 initialShares = getBorrowShares(id, onBehalf);
    uint256 initialTotalBorrow = getVirtualTotalBorrowAssets(id);
    uint256 initialTotalBorrowShares = getVirtualTotalBorrowShares(id);
    uint256 assetsDue = mathLibMulDivUp(initialShares, initialTotalBorrow, initialTotalBorrowShares);

    uint256 repaidAssets;
    repaidAssets, _ = repay(e, marketParams, assets, shares, onBehalf, data);

    require getBorrowShares(id, onBehalf) == 0;

    assert repaidAssets >= assetsDue;
}
