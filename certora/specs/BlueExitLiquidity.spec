methods {
    function withdraw(MorphoHarness.Market, uint256, uint256, address, address) external returns (uint256, uint256);
    function withdrawCollateral(MorphoHarness.Market, uint256, address, address) external returns (uint256, uint256);


    function supplyShares(MorphoHarness.Id, address) external returns uint256 envfree;
    function getVirtualTotalSupply(MorphoHarness.Id) external returns uint256 envfree;
    function getVirtualTotalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function collateral(MorphoHarness.Id, address) external returns uint256 envfree;

    function lastUpdate(MorphoHarness.Id) external returns uint256 envfree;

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
