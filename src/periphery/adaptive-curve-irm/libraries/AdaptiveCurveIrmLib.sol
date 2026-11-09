// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../../../interfaces/IMorpho.sol";
import {IAdaptiveCurveIrm} from "../interfaces/IAdaptiveCurveIrm.sol";

import {ExpLib} from "./ExpLib.sol";
import {UtilsLib} from "./UtilsLib.sol";
import {ConstantsLib} from "./ConstantsLib.sol";
import {MathLib, WAD_INT as WAD} from "./MathLib.sol";
import {SharesMathLib} from "../../../libraries/SharesMathLib.sol";
import {MathLib as MorphoMathLib} from "../../../libraries/MathLib.sol";
import {UtilsLib as MorphoUtilsLib} from "../../../libraries/UtilsLib.sol";

/// @dev Library to compute borrowRateView and expectedMarketBalances with only the market id.
/// @dev Must be used only for markets with an AdaptiveCurveIrm as irm.
library AdaptiveCurveIrmLib {
    using MathLib for int256;
    using UtilsLib for int256;
    using MorphoMathLib for uint256;
    using MorphoMathLib for uint128;
    using SharesMathLib for uint256;
    using MorphoUtilsLib for uint256;

    /// @dev Same as the MorphoBalancesLib.expectedMarketBalances function, but takes the market id as input.
    /// @dev Works only for markets with an AdaptiveCurveIrm as irm.
    /// @dev Returns the expected totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares.
    function expectedMarketBalances(address morpho, bytes32 id, address adaptiveCurveIrm)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        Market memory market = IMorpho(morpho).market(Id.wrap(id));

        uint256 elapsed = block.timestamp - market.lastUpdate;

        // Skipped if elapsed == 0 or totalBorrowAssets == 0 because interest would be null.
        if (elapsed != 0 && market.totalBorrowAssets != 0) {
            uint256 borrowRate = borrowRateView(id, market, adaptiveCurveIrm);
            uint256 interest = market.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            market.totalBorrowAssets += interest.toUint128();
            market.totalSupplyAssets += interest.toUint128();

            if (market.fee != 0) {
                uint256 feeAmount = interest.wMulDown(market.fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                // that total supply is already updated.
                uint256 feeShares =
                    feeAmount.toSharesDown(market.totalSupplyAssets - feeAmount, market.totalSupplyShares);
                market.totalSupplyShares += feeShares.toUint128();
            }
        }

        return (market.totalSupplyAssets, market.totalSupplyShares, market.totalBorrowAssets, market.totalBorrowShares);
    }

    /// @dev Same as the AdaptiveCurveIrm.borrowRateView function, but takes the market id as input.
    /// @dev Works only for markets with an AdaptiveCurveIrm as irm.
    /// @dev Returns avgRate.
    function borrowRateView(bytes32 id, Market memory market, address adaptiveCurveIrm)
        internal
        view
        returns (uint256)
    {
        (uint256 avgRate,) = _borrowRate(Id.wrap(id), market, adaptiveCurveIrm);
        return avgRate;
    }

    /// @dev Same as the AdaptiveCurveIrm.borrowRate function, but takes the market id as input.
    /// @dev Returns avgRate and endRateAtTarget.
    function _borrowRate(Id id, Market memory market, address adaptiveCurveIrm)
        internal
        view
        returns (uint256, int256)
    {
        // Safe "unchecked" cast because the utilization is smaller than 1 (scaled by WAD).
        int256 utilization =
            int256(market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0);

        int256 errNormFactor = utilization > ConstantsLib.TARGET_UTILIZATION
            ? WAD - ConstantsLib.TARGET_UTILIZATION
            : ConstantsLib.TARGET_UTILIZATION;
        int256 err = (utilization - ConstantsLib.TARGET_UTILIZATION).wDivToZero(errNormFactor);

        int256 startRateAtTarget = IAdaptiveCurveIrm(adaptiveCurveIrm).rateAtTarget(id);

        int256 avgRateAtTarget;
        int256 endRateAtTarget;

        if (startRateAtTarget == 0) {
            // First interaction.
            avgRateAtTarget = ConstantsLib.INITIAL_RATE_AT_TARGET;
            endRateAtTarget = ConstantsLib.INITIAL_RATE_AT_TARGET;
        } else {
            // The speed is assumed constant between two updates, but it is in fact not constant because of interest.
            // So the rate is always underestimated.
            int256 speed = ConstantsLib.ADJUSTMENT_SPEED.wMulToZero(err);
            // market.lastUpdate != 0 because it is not the first interaction with this market.
            // Safe "unchecked" cast because block.timestamp - market.lastUpdate <= block.timestamp <= type(int256).max.
            int256 elapsed = int256(block.timestamp - market.lastUpdate);
            int256 linearAdaptation = speed * elapsed;

            if (linearAdaptation == 0) {
                // If linearAdaptation == 0, avgRateAtTarget = endRateAtTarget = startRateAtTarget;
                avgRateAtTarget = startRateAtTarget;
                endRateAtTarget = startRateAtTarget;
            } else {
                // Formula of the average rate that should be returned to Morpho Blue:
                // avg = 1/T * ∫_0^T curve(startRateAtTarget*exp(speed*x), err) dx
                // The integral is approximated with the trapezoidal rule:
                // avg ~= 1/T * Σ_i=1^N [curve(f((i-1) * T/N), err) + curve(f(i * T/N), err)] / 2 * T/N
                // Where f(x) = startRateAtTarget*exp(speed*x)
                // avg ~= Σ_i=1^N [curve(f((i-1) * T/N), err) + curve(f(i * T/N), err)] / (2 * N)
                // As curve is linear in its first argument:
                // avg ~= curve([Σ_i=1^N [f((i-1) * T/N) + f(i * T/N)] / (2 * N), err)
                // avg ~= curve([(f(0) + f(T))/2 + Σ_i=1^(N-1) f(i * T/N)] / N, err)
                // avg ~= curve([(startRateAtTarget + endRateAtTarget)/2 + Σ_i=1^(N-1) f(i * T/N)] / N, err)
                // With N = 2:
                // avg ~= curve([(startRateAtTarget + endRateAtTarget)/2 + startRateAtTarget*exp(speed*T/2)] / 2, err)
                // avg ~= curve([startRateAtTarget + endRateAtTarget + 2*startRateAtTarget*exp(speed*T/2)] / 4, err)
                endRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation);
                int256 midRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation / 2);
                avgRateAtTarget = (startRateAtTarget + endRateAtTarget + 2 * midRateAtTarget) / 4;
            }
        }

        // Safe "unchecked" cast because avgRateAtTarget >= 0.
        return (uint256(_curve(avgRateAtTarget, err)), endRateAtTarget);
    }

    /// @dev Returns the rate for a given `_rateAtTarget` and an `err`.
    /// The formula of the curve is the following:
    /// r = ((1-1/C)*err + 1) * rateAtTarget if err < 0
    ///     ((C-1)*err + 1) * rateAtTarget else.
    function _curve(int256 _rateAtTarget, int256 err) internal pure returns (int256) {
        // Non negative because 1 - 1/C >= 0, C - 1 >= 0.
        int256 coeff = err < 0 ? WAD - WAD.wDivToZero(ConstantsLib.CURVE_STEEPNESS) : ConstantsLib.CURVE_STEEPNESS - WAD;
        // Non negative if _rateAtTarget >= 0 because if err < 0, coeff <= 1.
        return (coeff.wMulToZero(err) + WAD).wMulToZero(int256(_rateAtTarget));
    }

    /// @dev Returns the new rate at target, for a given `startRateAtTarget` and a given `linearAdaptation`.
    /// The formula is: max(min(startRateAtTarget * exp(linearAdaptation), maxRateAtTarget), minRateAtTarget).
    function _newRateAtTarget(int256 startRateAtTarget, int256 linearAdaptation) internal pure returns (int256) {
        // Non negative because MIN_RATE_AT_TARGET > 0.
        return startRateAtTarget.wMulToZero(ExpLib.wExp(linearAdaptation))
            .bound(ConstantsLib.MIN_RATE_AT_TARGET, ConstantsLib.MAX_RATE_AT_TARGET);
    }
}
