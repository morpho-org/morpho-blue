// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function libMulDivUp(uint256, uint256, uint256) external returns uint256 envfree;
    function libMulDivDown(uint256, uint256, uint256) external returns uint256 envfree;
    function libId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
    function optimizedId(MorphoHarness.MarketParams) external returns MorphoHarness.Id envfree;
}

// Check the summary of mulDivUp required by RatioMath.spec
rule checkSummaryMulDivUp(uint256 x, uint256 y, uint256 d) {
    uint256 result = libMulDivUp(x, y, d);
    assert result * d >= x * y;
}

// Check the summary of mulDivDown required by RatioMath.spec
rule checkSummaryMulDivDown(uint256 x, uint256 y, uint256 d) {
    uint256 result = libMulDivDown(x, y, d);
    assert result * d <= x * y;
}

// Check the munging of the MarketParams.id function.
rule checkSummaryId(MorphoHarness.MarketParams marketParams) {
    assert optimizedId(marketParams) == libId(marketParams);
}
