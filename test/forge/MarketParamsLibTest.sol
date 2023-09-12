// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {MarketParamsLib, MarketParams, Id} from "src/libraries/MarketParamsLib.sol";

contract MarketParamsLibTest is Test {
    using MarketParamsLib for MarketParams;

    function testMarketParamsId(MarketParams memory marketParamsFuzz) public {
        assertEq(Id.unwrap(marketParamsFuzz.id()), keccak256(abi.encode(marketParamsFuzz)));
    }
}
