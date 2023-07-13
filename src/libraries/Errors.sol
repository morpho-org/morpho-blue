// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Errors {
    string constant NOT_OWNER = "not owner";

    string constant LLTV_TOO_HIGH = "LLTV too high";

    string constant IRM_DISABLED = "IRM not enabled";

    string constant LLTV_DISABLED = "LLTV not enabled";

    string constant MARKET_CREATED = "market already exists";

    string constant MARKET_NOT_CREATED = "unknown market";

    string constant ZERO_AMOUNT = "zero amount";

    string constant INSUFFICIENT_COLLATERAL = "insufficient collateral";

    string constant INSUFFICIENT_LIQUIDITY = "insufficient liquidity";

    string constant HEALTHY_POSITION = "position is healthy";
}
