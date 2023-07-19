// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Errors {
    string internal constant NOT_OWNER = "not owner";

    string internal constant LLTV_TOO_HIGH = "LLTV too high";

    string internal constant IRM_NOT_ENABLED = "IRM not enabled";

    string internal constant LLTV_NOT_ENABLED = "LLTV not enabled";

    string internal constant MARKET_CREATED = "market already exists";

    string internal constant MARKET_NOT_CREATED = "unknown market";

    string internal constant ZERO_AMOUNT = "zero amount";

    string internal constant MANAGER_NOT_APPROVED = "not approved";

    string internal constant INSUFFICIENT_COLLATERAL = "insufficient collateral";

    string internal constant INSUFFICIENT_LIQUIDITY = "insufficient liquidity";

    string internal constant HEALTHY_POSITION = "position is healthy";
}
