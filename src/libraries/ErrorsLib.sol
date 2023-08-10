// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library ErrorsLib {
    string constant NOT_OWNER = "not owner";
    string constant LLTV_TOO_HIGH = "LLTV too high";
    string constant MAX_FEE_EXCEEDED = "MAX_FEE exceeded";
    string constant IRM_NOT_ENABLED = "IRM not enabled";
    string constant LLTV_NOT_ENABLED = "LLTV not enabled";
    string constant MARKET_CREATED = "market created";
    string constant MARKET_NOT_CREATED = "market not created";
    string constant INCONSISTENT_INPUT = "not exactly one zero";
    string constant ZERO_AMOUNT = "zero amount";
    string constant ZERO_ADDRESS = "zero address";
    string constant UNAUTHORIZED = "unauthorized";
    string constant INSUFFICIENT_COLLATERAL = "insufficient collateral";
    string constant INSUFFICIENT_LIQUIDITY = "insufficient liquidity";
    string constant HEALTHY_POSITION = "position is healthy";
    string constant INVALID_SIGNATURE = "invalid signature";
    string constant SIGNATURE_EXPIRED = "signature expired";
}
