// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library UniswapV3OracleLib {
    /// @notice Calculates time-weighted average price of a pool over a given duration.
    /// @param pool Address of the pool that we want to observe.
    /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted average.
    /// @return The time-weighted average price from (block.timestamp - secondsAgo) to block.timestamp.
    function consult(IUniswapV3Pool pool, uint32 secondsAgo) internal view returns (uint256) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
        // Always round to negative infinity.
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) arithmeticMeanTick--;

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);

        // Calculate price with better precision if it doesn't overflow when multiplied by itself.
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;

            return FullMath.mulDiv(ratioX192, 1e18, 1 << 192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);

            return FullMath.mulDiv(ratioX128, 1e18, 1 << 128);
        }
    }
}
