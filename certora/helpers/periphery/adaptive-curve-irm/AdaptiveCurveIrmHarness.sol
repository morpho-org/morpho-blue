// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AdaptiveCurveIrm} from "../../../../src/periphery/adaptive-curve-irm/AdaptiveCurveIrm.sol";
import {ExpLib} from "../../../../src/periphery/adaptive-curve-irm/libraries/ExpLib.sol";
import {UtilsLib} from "../../../../src/periphery/adaptive-curve-irm/libraries/UtilsLib.sol";
import {ConstantsLib} from "../../../../src/periphery/adaptive-curve-irm/libraries/ConstantsLib.sol";
import {MathLib as MorphoMathLib} from "../../../../src/libraries/MathLib.sol";
import {MarketParamsLib} from "../../../../src/libraries/MarketParamsLib.sol";
import {Id, MarketParams} from "../../../../src/interfaces/IMorpho.sol";

contract AdaptiveCurveIrmHarness is AdaptiveCurveIrm {
    using MarketParamsLib for MarketParams;

    constructor(address morpho) AdaptiveCurveIrm(morpho) {}

    function toId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }

    function wExpExt(int256 x) external pure returns (int256) {
        return ExpLib.wExp(x);
    }

    function boundExt(int256 x, int256 low, int256 high) external pure returns (int256) {
        return UtilsLib.bound(x, low, high);
    }

    function wDivDownExt(uint256 x, uint256 y) external pure returns (uint256) {
        return MorphoMathLib.wDivDown(x, y);
    }

    function minRateAtTarget() external pure returns (int256) {
        return ConstantsLib.MIN_RATE_AT_TARGET;
    }

    function maxRateAtTarget() external pure returns (int256) {
        return ConstantsLib.MAX_RATE_AT_TARGET;
    }

    function wexpUpperValue() external pure returns (int256) {
        return ExpLib.WEXP_UPPER_VALUE;
    }
}
