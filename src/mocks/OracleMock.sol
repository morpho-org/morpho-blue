// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IOracle} from "src/interfaces/IOracle.sol";

contract OracleMock is IOracle {
    uint256 internal _price;

    function price() external view returns (uint256, bool, bool) {
        return (_price, true, true);
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}
