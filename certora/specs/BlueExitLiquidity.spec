methods {
    function withdraw(MorphoHarness.Market, uint256, uint256, address, address) external returns (uint256, uint256);
    function withdrawCollateral(MorphoHarness.Market, uint256, address, address) external returns (uint256, uint256);


    function supplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getVirtualTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function borrowShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getVirtualTotalBorrow(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalBorrowShares(MorphoHarness.Id) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;

    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;

    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function getMarketId(MorphoHarness.Market) external returns MorphoHarness.Id envfree;
}

rule withdrawLiquidity(MorphoHarness.Market market, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    env e;
    MorphoHarness.Id id = getMarketId(market);

    require lastUpdate(id) == e.block.timestamp;

    uint256 initialShares = supplyShares(id, onBehalf);
    uint256 initialTotalSupply = getVirtualTotalSupply(id);
    uint256 initialTotalSupplyShares = getVirtualTotalSupplyShares(id);
    uint256 owedAssets = mathLibMulDivDown(initialShares, initialTotalSupply, initialTotalSupplyShares);

    uint256 withdrawnAssets;
    withdrawnAssets, _ = withdraw(e, market, assets, shares, onBehalf, receiver);

    assert withdrawnAssets <= owedAssets;
}

rule withdrawCollateralLiquidity(MorphoHarness.Market market, uint256 assets, address onBehalf, address receiver) {
    env e;
    MorphoHarness.Id id = getMarketId(market);

    uint256 initialCollateral = collateral(id, onBehalf);

    withdrawCollateral(e, market, assets, onBehalf, receiver);

    assert assets <= initialCollateral;
}

rule repayLiquidity(MorphoHarness.Market market, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    env e;
    MorphoHarness.Id id = getMarketId(market);

    require lastUpdate(id) == e.block.timestamp;

    uint256 initialShares = borrowShares(id, onBehalf);
    uint256 initialTotalBorrow = getVirtualTotalBorrow(id);
    uint256 initialTotalBorrowShares = getVirtualTotalBorrowShares(id);
    uint256 assetsDue = mathLibMulDivUp(initialShares, initialTotalBorrow, initialTotalBorrowShares);

    uint256 repaidAssets;
    repaidAssets, _ = repay(e, market, assets, shares, onBehalf, data);

    require borrowShares(id, onBehalf) == 0;

    assert repaidAssets >= assetsDue;
}
