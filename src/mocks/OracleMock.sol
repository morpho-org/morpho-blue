// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IOracle} from "src/interfaces/IOracle.sol";

contract OracleMock is IOracle {
    uint256 public price;

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}
