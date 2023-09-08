// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function _.borrowRate(MorphoHarness.MarketParams marketParams, MorphoHarness.Market) external => summaryBorrowRate() expect uint256;
}

ghost bool hasAccessedStorage;
ghost bool hasCallAfterAccessingStorage;
ghost bool hasReentrancyUnsafeCall;
ghost bool delegate_call;
ghost bool static_call;
ghost bool callIsBorrowRate;

function summaryBorrowRate() returns uint256 {
    uint256 result;
    callIsBorrowRate = true;
    return result;
}

hook ALL_SSTORE(uint loc, uint v) {
    hasAccessedStorage = true;
    hasReentrancyUnsafeCall = hasCallAfterAccessingStorage;
}

hook ALL_SLOAD(uint loc) uint v {
    hasAccessedStorage = true;
    hasReentrancyUnsafeCall = hasCallAfterAccessingStorage;
}

hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    if (callIsBorrowRate) {
        // The calls to borrow rate are trusted and don't count.
        callIsBorrowRate = false;
        hasCallAfterAccessingStorage = hasCallAfterAccessingStorage;
    } else {
        hasCallAfterAccessingStorage = hasAccessedStorage;
    }
}

hook DELEGATECALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    delegate_call = true;
}

hook STATICCALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    static_call = true;
}

// Check that no function is accessing storage, then making an external call other than to the IRM, and accessing storage again.
rule reentrancySafe(method f, calldataarg data, env e) {
    // Set up the initial state.
    require !callIsBorrowRate;
    require !hasAccessedStorage && !hasCallAfterAccessingStorage && !hasReentrancyUnsafeCall;
    f(e,data);
    assert !hasReentrancyUnsafeCall;
}

rule noDelegateCalls(method f, calldataarg data, env e) {
    // Set up the initial state.
    require !delegate_call;
    f(e,data);
    assert !delegate_call;
}

// This rule can be used to check which methods have static calls
// rule hasStaticCalls(method f, calldataarg data, env e) {
//     // Set up the initial state.
//     require !static_call;
//     f(e,data);
//     satisfy static_call;
// }
