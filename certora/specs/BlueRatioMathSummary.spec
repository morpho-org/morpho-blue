methods {
    function mathLibMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function mathLibMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
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
