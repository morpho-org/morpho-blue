// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Types} from "./Types.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Constants} from "src/libraries/Constants.sol";

/// @title InterestRatesManager
library InterestRatesManager {
    using WadRayMath for uint256;

    /// @notice Computes the new peer-to-peer indexes of a market given its parameters.
    function updateIndexes(Types.Market storage market, uint256 trancheNumber) internal {
        uint256 utilization =
            market.tranches[trancheNumber].totalBorrow.rayDiv(market.tranches[trancheNumber].totalSupply);
        (uint256 borrowRate, uint256 supplyRate) = computeRate(utilization);
        uint256 multiplierSupply =
            calculateCompoundedInterest(supplyRate, market.tranches[trancheNumber].lastUpdateTimestamp, block.timestamp);
        uint256 multiplierBorrow =
            calculateCompoundedInterest(borrowRate, market.tranches[trancheNumber].lastUpdateTimestamp, block.timestamp);
        market.tranches[trancheNumber].lastUpdateTimestamp = block.timestamp;
        market.tranches[trancheNumber].borrowIndex =
            market.tranches[trancheNumber].borrowIndex.rayMulUp(multiplierBorrow);
        market.tranches[trancheNumber].supplyIndex =
            market.tranches[trancheNumber].supplyIndex.rayMulDown(multiplierSupply);
    }

    function calculateCompoundedInterest(uint256 rate, uint256 lastUpdateTimestamp, uint256 currentTimestamp)
        internal
        pure
        returns (uint256)
    {
        uint256 exp = currentTimestamp - uint256(lastUpdateTimestamp);

        if (exp == 0) {
            return WadRayMath.RAY;
        }

        uint256 expMinusOne;
        uint256 expMinusTwo;
        uint256 basePowerTwo;
        uint256 basePowerThree;
        unchecked {
            expMinusOne = exp - 1;

            expMinusTwo = exp > 2 ? exp - 2 : 0;

            basePowerTwo = rate.rayMul(rate) / (Constants.SECONDS_PER_YEAR * Constants.SECONDS_PER_YEAR);
            basePowerThree = basePowerTwo.rayMul(rate) / Constants.SECONDS_PER_YEAR;
        }

        uint256 secondTerm = exp * expMinusOne * basePowerTwo;
        unchecked {
            secondTerm /= 2;
        }
        uint256 thirdTerm = exp * expMinusOne * expMinusTwo * basePowerThree;
        unchecked {
            thirdTerm /= 6;
        }

        return WadRayMath.RAY + (rate * exp) / Constants.SECONDS_PER_YEAR + secondTerm + thirdTerm;
    }

    /// @notice Need to define a function to define rate according to the utilization of the tranche.
    function computeRate(uint256 utilization) internal pure returns (uint256, uint256) {}
}
