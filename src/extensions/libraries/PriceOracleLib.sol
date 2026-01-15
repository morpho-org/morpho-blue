// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {IOracle} from "../../interfaces/IOracle.sol";
import {MathLib, WAD} from "../../libraries/MathLib.sol";

/// @title PriceOracleLib
/// @notice Library for price oracle validation with TWAP and multi-oracle support
library PriceOracleLib {
    using MathLib for uint256;

    /* ERRORS */

    error PriceDeviationTooHigh();
    error InvalidOraclePrice();
    error OracleStale();

    /* STRUCTS */

    struct PriceConfig {
        /// @notice Primary oracle address
        address primaryOracle;
        /// @notice Secondary oracle address (optional)
        address secondaryOracle;
        /// @notice Maximum allowed price deviation (scaled by WAD)
        /// @dev Example: 0.05e18 = 5% maximum deviation
        uint256 maxDeviation;
        /// @notice Maximum staleness period in seconds
        uint256 maxStaleness;
        /// @notice Whether to use TWAP
        bool useTWAP;
        /// @notice TWAP period in seconds
        uint256 twapPeriod;
    }

    struct TWAPData {
        /// @notice Cumulative price
        uint256 cumulativePrice;
        /// @notice Last update timestamp
        uint256 lastUpdateTime;
        /// @notice Last price
        uint256 lastPrice;
    }

    /* FUNCTIONS */

    /// @notice Get validated price with multi-oracle and deviation check
    /// @param config Price configuration
    /// @return price Validated price
    function getValidatedPrice(PriceConfig memory config) internal view returns (uint256 price) {
        require(config.primaryOracle != address(0), "Invalid primary oracle");

        // Get primary oracle price
        uint256 primaryPrice = IOracle(config.primaryOracle).price();
        require(primaryPrice > 0, "Invalid primary price");

        // If no secondary oracle, return primary price
        if (config.secondaryOracle == address(0)) {
            return primaryPrice;
        }

        // Get secondary oracle price
        uint256 secondaryPrice = IOracle(config.secondaryOracle).price();
        require(secondaryPrice > 0, "Invalid secondary price");

        // Check price deviation
        uint256 deviation = _calculateDeviation(primaryPrice, secondaryPrice);
        if (deviation > config.maxDeviation) {
            revert PriceDeviationTooHigh();
        }

        // Return average of two prices
        return (primaryPrice + secondaryPrice) / 2;
    }

    /// @notice Update TWAP data
    /// @param twapData Current TWAP data
    /// @param currentPrice Current price
    /// @return newTwapData Updated TWAP data
    function updateTWAP(TWAPData memory twapData, uint256 currentPrice)
        internal
        view
        returns (TWAPData memory newTwapData)
    {
        uint256 timeElapsed = block.timestamp - twapData.lastUpdateTime;

        // If first update or very long time passed, reset
        if (twapData.lastUpdateTime == 0 || timeElapsed > 1 days) {
            return TWAPData({
                cumulativePrice: currentPrice * block.timestamp,
                lastUpdateTime: block.timestamp,
                lastPrice: currentPrice
            });
        }

        // Update cumulative price
        uint256 newCumulativePrice = twapData.cumulativePrice + (twapData.lastPrice * timeElapsed);

        return TWAPData({
            cumulativePrice: newCumulativePrice,
            lastUpdateTime: block.timestamp,
            lastPrice: currentPrice
        });
    }

    /// @notice Calculate TWAP price
    /// @param twapData TWAP data
    /// @param period TWAP period in seconds
    /// @return twapPrice Time-weighted average price
    function calculateTWAP(TWAPData memory twapData, uint256 period) internal view returns (uint256 twapPrice) {
        if (twapData.lastUpdateTime == 0 || block.timestamp < twapData.lastUpdateTime + period) {
            // Not enough data, return last price
            return twapData.lastPrice;
        }

        uint256 timeElapsed = block.timestamp - (twapData.lastUpdateTime - period);
        return twapData.cumulativePrice / timeElapsed;
    }

    /// @notice Check if price has deviated too much from previous price
    /// @param oldPrice Previous price
    /// @param newPrice New price
    /// @param maxDeviation Maximum allowed deviation (scaled by WAD)
    /// @return Whether price is within acceptable range
    function isPriceWithinDeviation(uint256 oldPrice, uint256 newPrice, uint256 maxDeviation)
        internal
        pure
        returns (bool)
    {
        if (oldPrice == 0) return true;

        uint256 deviation = _calculateDeviation(oldPrice, newPrice);
        return deviation <= maxDeviation;
    }

    /// @notice Calculate price deviation percentage
    /// @param price1 First price
    /// @param price2 Second price
    /// @return deviation Deviation scaled by WAD
    function _calculateDeviation(uint256 price1, uint256 price2) private pure returns (uint256 deviation) {
        if (price1 == 0 || price2 == 0) return type(uint256).max;

        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 avg = (price1 + price2) / 2;

        return diff.wDivDown(avg);
    }

    /// @notice Validate price freshness
    /// @param lastUpdateTime Last price update timestamp
    /// @param maxStaleness Maximum staleness in seconds
    function validateFreshness(uint256 lastUpdateTime, uint256 maxStaleness) internal view {
        if (block.timestamp > lastUpdateTime + maxStaleness) {
            revert OracleStale();
        }
    }
}

