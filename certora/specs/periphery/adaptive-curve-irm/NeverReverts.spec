// SPDX-License-Identifier: MIT

methods {
    function rateAtTarget(AdaptiveCurveIrmHarness.Id) external returns (int256) envfree;
    function toId(AdaptiveCurveIrmHarness.MarketParams) external returns (AdaptiveCurveIrmHarness.Id) envfree;
    function minRateAtTarget() external returns (int256) envfree;
    function maxRateAtTarget() external returns (int256) envfree;
    function wexpUpperValue() external returns (int256) envfree;

    function ExpLib.wExp(int256 x) internal returns (int256) => summaryWExp(x);
    function UtilsLib.bound(int256 x, int256 low, int256 high) internal returns (int256) => summaryBound(x, low, high);
    function MathLib.wDivDown(uint256 x, uint256 y) internal returns (uint256) => summaryWDivDown(x, y);
}

// Summary function for wExp, sound because wExpBounded in ExpLibSummary checks that it never reverts and proves the property being required.
function summaryWExp(int256 x) returns int256 {
    int256 result;
    require result >= 0 && result <= wexpUpperValue();
    return result;
}

// Summary function for bound, sound because boundInRange in ExpLibSummary checks that it never reverts and proves the property being required.
function summaryBound(int256 x, int256 low, int256 high) returns int256 {
    assert low <= high;
    int256 result;
    require result >= low && result <= high;
    return result;
}

// Summary function for wDivDown, sound because wDivDownBounded in ExpLibSummary checks that it never reverts and proves the property being required.
function summaryWDivDown(uint256 x, uint256 y) returns uint256 {
    assert x <= max_uint128 && y <= max_uint128;
    assert y > 0;
    assert x <= y;
    uint256 result;
    require result <= 10^18;
    return result;
}

invariant rateAtTargetInRange(AdaptiveCurveIrmHarness.Id id)
    rateAtTarget(id) == 0 ||
    (rateAtTarget(id) >= minRateAtTarget() && rateAtTarget(id) <= maxRateAtTarget());

// This rule proves that borrowRateView never reverts when called with msg.value == 0.
rule borrowRateViewNeverReverts(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    // morpho-blue proves rule noTimeTravel in ConsistentState.
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply in ConsistentState.
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Unrealistically high timestamp.
    require e.block.timestamp < 2^128;

    // borrowRateView is not payable.
    require e.msg.value == 0;

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

// This rule proves that borrowRate never reverts when called by MORPHO, with msg.value == 0.
rule borrowRateNeverReverts(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    // morpho-blue proves rule noTimeTravel in ConsistentState.
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply in ConsistentState.
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Unrealistically high timestamp.
    require e.block.timestamp < 2^128;

    // borrowRate rejects every caller other than MORPHO.
    require e.msg.sender == currentContract.MORPHO;
    // borrowRate is not payable.
    require e.msg.value == 0;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}
