// SPDX-License-Identifier: MIT

methods {
    function wExpExt(int256) external returns (int256) envfree;
    function boundExt(int256, int256, int256) external returns (int256) envfree;
    function wDivDownExt(uint256, uint256) external returns (uint256) envfree;
    function wexpUpperValue() external returns (int256) envfree;
}

rule wExpBounded(int256 x) {
    int256 result = wExpExt@withrevert(x);
    bool reverted = lastReverted;

    assert !reverted;
    assert result >= 0 && result <= wexpUpperValue();
}

rule boundInRange(int256 x, int256 low, int256 high) {
    // AdaptiveCurveIrm passes low=MIN_RATE_AT_TARGET, high=MAX_RATE_AT_TARGET, and MIN < MAX.
    require low <= high;

    int256 result = boundExt@withrevert(x, low, high);
    bool reverted = lastReverted;

    assert !reverted;
    assert result >= low && result <= high;
}

rule wDivDownBounded(uint256 x, uint256 y) {
    // Market.totalBorrowAssets and Market.totalSupplyAssets are uint128.
    require x <= max_uint128 && y <= max_uint128;
    // AdaptiveCurveIrm only evaluates wDivDown when totalSupplyAssets > 0.
    require y > 0;
    // morpho-blue proves invariant borrowLessThanSupply in ConsistentState.
    require x <= y;

    uint256 result = wDivDownExt@withrevert(x, y);
    bool reverted = lastReverted;

    assert !reverted;
    assert result <= 10^18;
}
