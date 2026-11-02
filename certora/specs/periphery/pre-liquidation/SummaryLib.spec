// SPDX-License-Identifier: MIT

using MorphoHarness as MORPHO;
using Util as Util;

methods {
    function MORPHO.virtualTotalBorrowAssets(PreLiquidation.Id) external returns (uint256) envfree;
    function MORPHO.virtualTotalBorrowShares(PreLiquidation.Id) external returns (uint256) envfree;
    function MORPHO.borrowShares(PreLiquidation.Id, address) external returns (uint256) envfree;
    function MORPHO.collateral(PreLiquidation.Id, address) external returns (uint256) envfree;
    function MORPHO.lastUpdate(PreLiquidation.Id) external returns (uint256) envfree;

    function Util.libId(PreLiquidation.MarketParams) external returns (PreLiquidation.Id) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

function summaryWMulDown(uint256 x, uint256 y) returns uint256 {
    return summaryMulDivDown(x, y, WAD());
}

function summaryWDivDown(uint256 x, uint256 y) returns uint256 {
    return summaryMulDivDown(x, WAD(), y);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    return require_uint256((x * y) / d);
}

function summaryWDivUp(uint256 x, uint256 y) returns uint256 {
    return summaryMulDivUp(x, WAD(), y);
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    // Safe require because the reference implementation would revert.
    return require_uint256((x * y + (d - 1)) / d);
}

definition summaryExactlyOneZero(uint256 assets, uint256 shares) returns bool = (assets == 0 && shares != 0) || (assets != 0 && shares == 0);

persistent ghost uint256 lastPrice;

persistent ghost bool priceChanged;

function mockPrice() returns uint256 {
    uint256 updatedPrice;
    if (updatedPrice != lastPrice) {
        priceChanged = true;
        lastPrice = updatedPrice;
    }
    return updatedPrice;
}

// Ensure this function is only used when no interest is accrued, or enforce that the last update matches the current timestamp.
function positionAsAssets(address borrower) returns (uint256, uint256) {
    uint256 borrowerShares = MORPHO.borrowShares(currentContract.ID, borrower);
    uint256 borrowerCollateral = MORPHO.collateral(currentContract.ID, borrower);

    uint256 collateralQuoted = summaryMulDivDown(borrowerCollateral, mockPrice(), ORACLE_PRICE_SCALE());

    require collateralQuoted > 0, "safe because the implementation would revert, see rule zeroCollateralQuotedReverts";

    uint256 totalAssets = MORPHO.virtualTotalBorrowAssets(currentContract.ID);
    uint256 totalShares = MORPHO.virtualTotalBorrowShares(currentContract.ID);
    uint256 borrowed = summaryMulDivUp(borrowerShares, totalAssets, totalShares);

    return (borrowed, collateralQuoted);
}

function getLtv(address borrower) returns uint256 {
    uint256 borrowed;
    uint256 collateralQuoted;

    borrowed, collateralQuoted = positionAsAssets(borrower);

    return summaryWDivUp(borrowed, collateralQuoted);
}

// Safe requires because the implementation would revert.
definition computeLinearCombination(uint256 ltv, uint256 lltv, uint256 preLltv, uint256 yAtPreLltv, uint256 yAtLltv) returns uint256 = require_uint256(summaryWMulDown(summaryWDivDown(require_uint256(ltv - preLltv), require_uint256(lltv - preLltv)), require_uint256(yAtLltv - yAtPreLltv)) + yAtPreLltv);
