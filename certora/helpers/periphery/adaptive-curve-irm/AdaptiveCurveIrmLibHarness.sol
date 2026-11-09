// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AdaptiveCurveIrmLib} from "../../../../src/periphery/adaptive-curve-irm/libraries/AdaptiveCurveIrmLib.sol";
import {MorphoBalancesLib} from "../../../../src/libraries/periphery/MorphoBalancesLib.sol";
import {Id, Market, MarketParams, IMorpho} from "../../../../src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../../../src/libraries/MarketParamsLib.sol";

contract AdaptiveCurveIrmLibHarness {
    using MarketParamsLib for MarketParams;

    function adaptiveCurveIrmLibExpectedMarketBalances(IMorpho morpho, Id id, address adaptiveCurveIrm)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return AdaptiveCurveIrmLib.expectedMarketBalances(address(morpho), Id.unwrap(id), adaptiveCurveIrm);
    }

    function morphoBalancesLibExpectedMarketBalances(IMorpho morpho, MarketParams memory marketParams)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return MorphoBalancesLib.expectedMarketBalances(morpho, marketParams);
    }

    function borrowRateView(Id id, Market memory market, address adaptiveCurveIrm) external view returns (uint256) {
        return AdaptiveCurveIrmLib.borrowRateView(Id.unwrap(id), market, adaptiveCurveIrm);
    }

    function toId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }
}
