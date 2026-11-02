// SPDX-License-Identifier: MIT

import "ConsistentInstantiation.spec";

methods {
    function _.price() external => mockPrice() expect(uint256);
}

// Checks that onMorphoRepay is only triggered by Morpho.
rule onMorphoRepaySenderValidation(env e, uint256 repaidAssets, bytes data) {
    onMorphoRepay@withrevert(e, repaidAssets, data);
    assert e.msg.sender != currentContract.MORPHO => lastReverted;
}

// Check that preLiquidate reverts when its inputs are not validated.
rule preLiquidateInputValidation(env e, address borrower, uint256 seizedAssets, uint256 repaidShares, bytes data) {
    requireInvariant preLltvConsistent();
    requireInvariant preLCFConsistent();
    requireInvariant preLIFConsistent();

    preLiquidate@withrevert(e, borrower, seizedAssets, repaidShares, data);
    assert !summaryExactlyOneZero(seizedAssets, repaidShares) => lastReverted;
}

// Check that collateralQuoted == 0 would revert by failing require-statements.
rule zeroCollateralQuotedReverts(env e, address borrower, uint256 seizedAssets, bytes data) {
    requireInvariant preLltvConsistent();

    uint256 collateralQuoted;
    uint256 borrowed;

    uint256 higherBound = summaryWMulDown(collateralQuoted, currentContract.LLTV);
    uint256 lowerBound = summaryWMulDown(collateralQuoted, currentContract.PRE_LLTV);

    assert collateralQuoted == 0 => (lowerBound >= borrowed || borrowed > higherBound);
}

// Check that pre-liquidating a position such that LTV <= PRE_LLTV reverts.
// This also implies that LTV > PRE_LLTV when borrowed > collateralQuoted.summaryWMulDown(PRE_LLTV).
rule nonLiquidatablePositionReverts(env e, address borrower, uint256 seizedAssets, bytes data) {
    requireInvariant preLltvConsistent();
    requireInvariant preLCFConsistent();
    requireInvariant preLIFConsistent();

    // Ensure that no interest is accumulated.
    // Safe require as the invariant ID == marketParams().id() holds.
    require MORPHO.lastUpdate(currentContract.ID) == e.block.timestamp;

    uint256 ltv = getLtv(borrower);

    preLiquidate@withrevert(e, borrower, seizedAssets, 0, data);

    // Ensure the price is unchanged in the preLiquidate call.
    require !priceChanged;

    assert ltv <= currentContract.PRE_LLTV => lastReverted;
}

// Check that pre-liquidating a position such that LTV > LLTV would revert.
rule liquidatablePositionReverts(env e, address borrower, uint256 seizedAssets, bytes data) {
    requireInvariant preLltvConsistent();
    requireInvariant preLCFConsistent();
    requireInvariant preLIFConsistent();

    // Ensure that no interest is accumulated.
    // Safe require as the invariant ID == marketParams().id() holds.
    require MORPHO.lastUpdate(currentContract.ID) == e.block.timestamp;

    uint256 ltv = getLtv(borrower);

    preLiquidate@withrevert(e, borrower, seizedAssets, 0, data);

    // Ensure the price is unchanged in the preLiquidate call.
    require !priceChanged;

    assert ltv > currentContract.LLTV => lastReverted;
}

// Check that a pre-liquidation that repays more shares than available or allowed by the preLCF reverts.
rule excessivePreliquidationWithAssetsReverts(env e, address borrower, uint256 seizedAssets, bytes data) {
    requireInvariant preLltvConsistent();
    requireInvariant preLCFConsistent();
    requireInvariant preLIFConsistent();

    // Ensure that no interest is accumulated.
    // Safe require as the invariant ID == marketParams().id() holds.
    require MORPHO.lastUpdate(currentContract.ID) == e.block.timestamp;

    uint256 ltv = getLtv(borrower);

    uint256 preLIF = computeLinearCombination(ltv, currentContract.LLTV, currentContract.PRE_LLTV, currentContract.PRE_LIF_1, currentContract.PRE_LIF_2);

    uint256 seizedAssetsQuoted = summaryMulDivUp(seizedAssets, mockPrice(), ORACLE_PRICE_SCALE());

    uint256 totalAssets = MORPHO.virtualTotalBorrowAssets(currentContract.ID);
    uint256 totalShares = MORPHO.virtualTotalBorrowShares(currentContract.ID);
    uint256 repaidShares = summaryMulDivUp(summaryWDivUp(seizedAssetsQuoted, preLIF), totalShares, totalAssets);

    uint256 preLCF = computeLinearCombination(ltv, currentContract.LLTV, currentContract.PRE_LLTV, currentContract.PRE_LCF_1, currentContract.PRE_LCF_2);

    uint256 repayableShares = summaryWMulDown(MORPHO.borrowShares(currentContract.ID, borrower), preLCF);

    preLiquidate@withrevert(e, borrower, seizedAssets, 0, data);

    // Ensure the price is unchanged in the preLiquidate call.
    require !priceChanged;

    assert repaidShares > repayableShares => lastReverted;
}

// Check that repaying more shares than available or allowed by the preLCF would revert.
rule excessivePreliquidationWithSharesReverts(env e, address borrower, uint256 repaidShares, bytes data) {
    requireInvariant preLltvConsistent();
    requireInvariant preLCFConsistent();
    requireInvariant preLIFConsistent();

    // Ensure that no interest is accumulated.
    // Safe require as the invariant ID == marketParams().id() holds.
    require MORPHO.lastUpdate(currentContract.ID) == e.block.timestamp;

    uint256 borrowerShares = MORPHO.borrowShares(currentContract.ID, borrower);

    uint256 ltv = getLtv(borrower);

    uint256 preLCF = computeLinearCombination(ltv, currentContract.LLTV, currentContract.PRE_LLTV, currentContract.PRE_LCF_1, currentContract.PRE_LCF_2);

    uint256 repayableShares = summaryWMulDown(borrowerShares, preLCF);

    preLiquidate@withrevert(e, borrower, 0, repaidShares, data);

    // Ensure the price is unchanged in the preLiquidate call.
    require !priceChanged;

    assert repaidShares > repayableShares => lastReverted;
}
