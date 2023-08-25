methods {
    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function marketLibId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

// Check the summaries required by BlueRatioMath.spec
rule checkSummaryMulDivUp(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivUp(x, y, d);
    assert result * d >= x * y;
}

rule checkSummaryMulDivDown(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivDown(x, y, d);
    assert result * d <= x * y;
}

rule checkSummaryId(MorphoHarness.MarketParams martketParams) {
    assert marketLibId(marketParams) == getMarketId(marketParams);
}
