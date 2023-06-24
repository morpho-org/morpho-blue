// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracle} from "src/Market.sol";

contract OracleMock is IOracle {
    uint public price;

    function setPrice(uint newPrice) external {
        price = newPrice;
    }
}
