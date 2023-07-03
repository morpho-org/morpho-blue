// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Types} from "src/libraries/Types.sol";

interface ICallBack {
    function callBack(Types.MarketParams calldata params, uint256 lltv, Types.CallbackData[] memory callbackData)
        external;
}
