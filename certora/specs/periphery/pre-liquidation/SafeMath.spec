// SPDX-License-Identifier: MIT

definition WAD() returns mathint = 10 ^ 18;

function summaryWMulDown(mathint x, mathint y) returns mathint {
    return (x * y) / WAD();
}

function summaryWDivUp(mathint x, mathint y) returns mathint {
    return (x * WAD() + (y - 1)) / y;
}

// Check that LTV <= LLTV is equivalent to borrowed <= (collateralQuoted * LLTV) / WAD.
rule ltvAgainstLltvEquivalentCheck() {
    uint256 borrowed;
    uint256 collateralQuoted;
    uint256 lltv;

    require collateralQuoted > 0, "safe because the implementation would revert, see rule zeroCollateralQuotedReverts";

    mathint ltv = summaryWDivUp(borrowed, collateralQuoted);

    assert ltv <= lltv <=> borrowed <= summaryWMulDown(collateralQuoted, lltv);
}

// Check that substracting the PRE_LLTV to LTV wont underflow.
rule ltvAgainstPreLltvEquivalentCheck() {
    uint256 borrowed;
    uint256 collateralQuoted;
    uint256 preLltv;

    require collateralQuoted > 0, "safe because the implementation would revert, see rule zeroCollateralQuotedReverts";

    mathint ltv = summaryWDivUp(borrowed, collateralQuoted);

    assert ltv > preLltv <=> borrowed > summaryWMulDown(collateralQuoted, preLltv);
}
