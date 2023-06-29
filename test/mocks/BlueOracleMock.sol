// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IBlueOracle} from "../../src/interfaces/IBlueOracle.sol";

contract BlueOracleMock is IBlueOracle {
    uint256 m;
    int256 e;

    function query() external view returns (IBlueOracle.BlueOracleResult memory result) {
        result.priceMantissa = m;
        result.priceExponent = e;
    }

    function set(uint256 _m, int256 _e) external {
        m = _m;
        e = _e;
    }
}
