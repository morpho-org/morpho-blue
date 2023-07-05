// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IRateModel} from "../interfaces/IRateModel.sol";

import {MarketKey, MarketState} from "../libraries/Types.sol";

contract RateModelMock is IRateModel {
    function accrue(MarketKey calldata marketKey, MarketState calldata state, uint256 dTimestamp)
        external
        view
        returns (uint256)
    {
        return 0;
    }
}
