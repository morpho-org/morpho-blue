methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function getMarketId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function marketLibId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

// Check the summary of mulDivUp required by RatioMath.spec
rule checkSummaryMulDivUp(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivUp(x, y, d);
    assert result * d >= x * y;
}

// Check the summary of mulDivDown required by RatioMath.spec
rule checkSummaryMulDivDown(uint256 x, uint256 y, uint256 d) {
    uint256 result = mathLibMulDivDown(x, y, d);
    assert result * d <= x * y;
}

// Check the munging of the MarketParams.id function.
// This rule cannot be checked because it is not possible disable the keccak256 summary for the moment.
// rule checkSummaryId(MorphoHarness.MarketParams marketParams) {
//     assert marketLibId(marketParams) == getMarketId(marketParams);
// }
