// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library ErrorsLib {
    string internal constant NOT_OWNER = "not owner";

    string internal constant LLTV_TOO_HIGH = "LLTV too high";

    string internal constant MAX_FEE_EXCEEDED = "MAX_FEE exceeded";

    string internal constant IRM_NOT_ENABLED = "IRM not enabled";

    string internal constant LLTV_NOT_ENABLED = "LLTV not enabled";

    string internal constant MARKET_CREATED = "market created";

    string internal constant MARKET_NOT_CREATED = "market not created";

    string internal constant ZERO_AMOUNT = "zero amount";

    string internal constant ZERO_SHARES = "zero shares";

    string internal constant ZERO_ADDRESS = "zero address";

    string internal constant UNAUTHORIZED = "unauthorized";

    string internal constant INSUFFICIENT_COLLATERAL = "insufficient collateral";

    string internal constant INSUFFICIENT_LIQUIDITY = "insufficient liquidity";

    string internal constant HEALTHY_POSITION = "position is healthy";

    string internal constant INVALID_SIGNATURE = "invalid signature";

    string internal constant SIGNATURE_EXPIRED = "signature expired";
}
