// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function libMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function libMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function refId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

// Check the summary of MathLib.mulDivUp required by RatioMath.spec
rule checkSummaryMulDivUp(uint256 x, uint256 y, uint256 d) {
    uint256 result = libMulDivUp(x, y, d);
    assert result * d >= x * y;
}

// Check the summary of MathLib.mulDivDown required by RatioMath.spec
rule checkSummaryMulDivDown(uint256 x, uint256 y, uint256 d) {
    uint256 result = libMulDivDown(x, y, d);
    assert result * d <= x * y;
}

// Check the summary of MarketParamsLib.id required by Liveness.spec
rule checkSummaryId(MorphoHarness.MarketParams marketParams) {
    assert libId(marketParams) == refId(marketParams);
}
