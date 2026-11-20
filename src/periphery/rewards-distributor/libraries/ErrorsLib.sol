// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing error messages.
library ErrorsLib {
    string internal constant ZERO_ADDRESS = "zero address";
    string internal constant UNKNOWN_CAMPAIGN = "unknown campaign";
    string internal constant NOT_UPDATER_ROLE = "caller has not the updater role";
    string internal constant ALREADY_PENDING = "already pending";
    string internal constant ALREADY_SET = "already set";
    string internal constant NO_PENDING_ROOT = "no pending root";
    string internal constant TIMELOCK_NOT_EXPIRED = "timelock is not expired";
    string internal constant ROOT_NOT_SET = "root is not set";
    string internal constant INVALID_PROOF_OR_EXPIRED = "invalid proof or expired";
    string internal constant CLAIMABLE_TOO_LOW = "claimable too low";
    string internal constant INSUFFICIENT_BALANCE = "insufficient campaign balance";
}
