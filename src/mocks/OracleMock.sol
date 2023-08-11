// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";

import {FixedPointMathLib, WAD} from "src/libraries/FixedPointMathLib.sol";

contract OracleMock is IOracle {
    uint256 internal _price;

    function price() external view returns (uint256, uint256) {
        return (_price, WAD);
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}
