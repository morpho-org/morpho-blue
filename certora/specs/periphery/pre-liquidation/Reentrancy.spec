// SPDX-License-Identifier: MIT

// True when storage has been accessed with either a SSTORE or a SLOAD.
persistent ghost bool hasAccessedStorage;

hook ALL_SSTORE(uint loc, uint v) {
    hasAccessedStorage = true;
}

hook ALL_SLOAD(uint loc) uint v {
    hasAccessedStorage = true;
}

// Check that no function is accessing storage.
rule reentrancySafe(method f, env e, calldataarg data) {
    // Set up the initial state.
    require !hasAccessedStorage;
    f(e, data);
    assert !hasAccessedStorage;
}
