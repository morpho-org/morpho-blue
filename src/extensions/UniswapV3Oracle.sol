// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {UniswapV3OracleLib} from "./libraries/UniswapV3OracleLib.sol";

contract ChainlinkAggregatorOracle is IOracle {
    using FixedPointMathLib for uint256;
    using UniswapV3OracleLib for IUniswapV3Pool;

    IUniswapV3Pool internal immutable _POOL;

    uint32 private immutable _DELAY;

    constructor(address pool, uint32 delay) {
        _POOL = IUniswapV3Pool(pool);
        _DELAY = delay;
    }

    function price() external view returns (uint256, bool, bool) {
        return (_POOL.consult(_DELAY), true, true);
    }
}
