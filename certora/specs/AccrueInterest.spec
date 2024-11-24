// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;

    function Util.maxFee() external returns uint256 envfree;

    function MathLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns uint256 => ghostMulDivDown(a,b,c);
    function MathLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns uint256 => ghostMulDivUp(a,b,c);
    function MathLib.wTaylorCompounded(uint256 a, uint256 b) internal returns uint256 => ghostTaylorCompounded(a, b);
    // We assume here that all external functions will not access storage, since we cannot show commutativity otherwise.
    // We also need to assume that the price and borrow rate return always the same value (and do not depend on msg.origin), so we use ghost functions for them.
    function _.borrowRate(MorphoHarness.MarketParams marketParams, MorphoHarness.Market market) external with (env e) => ghostBorrowRate(marketParams.irm, e.block.timestamp) expect uint256;
    function _.price() external with (env e) => ghostOraclePrice(e.block.timestamp) expect uint256;
    function _.transfer(address to, uint256 amount) external => ghostTransfer(to, amount) expect bool;
    function _.transferFrom(address from, address to, uint256 amount) external => ghostTransferFrom(from, to, amount) expect bool;
    function _.onMorphoLiquidate(uint256, bytes) external => NONDET;
    function _.onMorphoRepay(uint256, bytes) external => NONDET;
    function _.onMorphoSupply(uint256, bytes) external => NONDET;
    function _.onMorphoSupplyCollateral(uint256, bytes) external => NONDET;
    function _.onMorphoFlashLoan(uint256, bytes) external => NONDET;
}

ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;
ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256;
ghost ghostTaylorCompounded(uint256, uint256) returns uint256;
ghost ghostBorrowRate(address, uint256) returns uint256;
ghost ghostOraclePrice(uint256) returns uint256;
ghost ghostTransfer(address, uint256) returns bool;
ghost ghostTransferFrom(address, address, uint256) returns bool;


// Check that calling accrueInterest first has no effect.
// This is because supply should call accrueInterest itself.
rule supplyAccruesInterest(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    // Safe require because timestamps cannot realistically be that large.
    require e.block.timestamp < 2^128;

    storage init = lastStorage;

    accrueInterest(e, marketParams);
    supply(e, marketParams, assets, shares, onBehalf, data);
    storage afterBoth = lastStorage;

    supply(e, marketParams, assets, shares, onBehalf, data) at init;
    storage afterOne = lastStorage;

    assert afterBoth == afterOne;
}

// Check that calling accrueInterest first has no effect.
// This is because withdraw should call accrueInterest itself.
rule withdrawAccruesInterest(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    // Safe require because timestamps cannot realistically be that large.
    require e.block.timestamp < 2^128;

    storage init = lastStorage;

    accrueInterest(e, marketParams);
    withdraw(e, marketParams, assets, shares, onBehalf, receiver);
    storage afterBoth = lastStorage;

    withdraw(e, marketParams, assets, shares, onBehalf, receiver) at init;
    storage afterOne = lastStorage;

    assert afterBoth == afterOne;
}

// Check that calling accrueInterest first has no effect.
// This is because borrow should call accrueInterest itself.
rule borrowAccruesInterest(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    // Safe require because timestamps cannot realistically be that large.
    require e.block.timestamp < 2^128;

    storage init = lastStorage;

    accrueInterest(e, marketParams);
    borrow(e, marketParams, assets, shares, onBehalf, receiver);
    storage afterBoth = lastStorage;

    borrow(e, marketParams, assets, shares, onBehalf, receiver) at init;
    storage afterOne = lastStorage;

    assert afterBoth == afterOne;
}

// Check that calling accrueInterest first has no effect.
// This is because repay should call accrueInterest itself.
rule repayAccruesInterest(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    // Safe require because timestamps cannot realistically be that large.
    require e.block.timestamp < 2^128;

    storage init = lastStorage;

    accrueInterest(e, marketParams);
    repay(e, marketParams, assets, shares, onBehalf, data);
    storage afterBoth = lastStorage;

    repay(e, marketParams, assets, shares, onBehalf, data) at init;
    storage afterOne = lastStorage;

    assert afterBoth == afterOne;
}

// Show that accrueInterest commutes with other state changing rules.
// We exclude view functions, because:
// (a) we cannot check the return value and for storage commutativity is trivial, and
// (b) most view functions, e.g. totalSupplyShares, are not commutative, i.e. they return a different value if called before accrueInterest is called.
// We also exclude setFeeRecipient, as it is known to be not commutative.
rule accrueInterestCommutesExceptForSetFeeRecipient(method f, calldataarg args)
filtered {
    f -> !f.isView && f.selector != sig:setFeeRecipient(address).selector
}
{
    env e1;
    env e2;
    MorphoHarness.MarketParams marketParams;

    // Assume interactions to happen at the same block.
    require e1.block.timestamp == e2.block.timestamp;
    // Safe require because timestamps cannot realistically be that large.
    require e1.block.timestamp < 2^128;

    storage init = lastStorage;

    accrueInterest(e1, marketParams);
    f@withrevert(e2, args);
    bool revert1 = lastReverted;
    storage store1 = lastStorage;


    f@withrevert(e2, args) at init;
    bool revert2 = lastReverted;
    accrueInterest(e1, marketParams);
    storage store2 = lastStorage;

    assert revert1 <=> revert2;
    assert store1 == store2;
}
