// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {MarketKey, MarketState} from "../libraries/Types.sol";

interface IRateModel {
    function accrue(MarketKey calldata marketKey, MarketState calldata state, uint256 dTimestamp)
        external
        view
        returns (uint256 accrual);
}
