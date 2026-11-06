// SPDX-License-Identifier: MIT

using AdaptiveCurveIrm as AdaptiveCurveIrm;
using AdaptiveCurveIrmLibHarness as AdaptiveCurveIrmLibHarness;

methods {
    function AdaptiveCurveIrmLibHarness.toId(AdaptiveCurveIrm.MarketParams) external returns (AdaptiveCurveIrm.Id) envfree;

    function _.rateAtTarget(AdaptiveCurveIrm.Id id) external => DISPATCHER(true);
}

// Rule: the lib returns the same result as the contract
rule borrowRateViewEquivalence(env e, AdaptiveCurveIrm.MarketParams marketParams, AdaptiveCurveIrm.Market market) {
    AdaptiveCurveIrm.Id id = AdaptiveCurveIrmLibHarness.toId(marketParams);

    uint256 originalRate = AdaptiveCurveIrm.borrowRateView(e, marketParams, market);
    uint256 libRate = AdaptiveCurveIrmLibHarness.borrowRateView(e, id, market, AdaptiveCurveIrm);

    assert originalRate == libRate;
}

// Rule: the lib reverts exactly when the contract reverts
rule borrowRateView2Liveness(env e, AdaptiveCurveIrm.MarketParams marketParams, AdaptiveCurveIrm.Market market) {
    AdaptiveCurveIrm.Id id = AdaptiveCurveIrmLibHarness.toId(marketParams);

    AdaptiveCurveIrm.borrowRateView@withrevert(e, marketParams, market);
    bool originalReverted = lastReverted;

    AdaptiveCurveIrmLibHarness.borrowRateView@withrevert(e, id, market, AdaptiveCurveIrm);
    bool view2Reverted = lastReverted;

    assert originalReverted == view2Reverted;
}
