// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";

import {FixedPointMathLib, WAD} from "../libraries/FixedPointMathLib.sol";

contract OracleMock is IOracle {
    uint256 public price;

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}
