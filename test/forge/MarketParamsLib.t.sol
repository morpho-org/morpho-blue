// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Id, MarketParams} from "src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "src/libraries/MarketParamsLib.sol";

contract MarketParamsLibTest is Test {
    using MarketParamsLib for MarketParams;

    function testEquivalenceSolidity(MarketParams memory marketParams) public {
        bytes32 expectedId = keccak256(abi.encode(marketParams));
        assertEq(Id.unwrap(marketParams.id()), expectedId);
    }
}
