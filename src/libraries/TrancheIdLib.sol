// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {TrancheId} from "./Types.sol";
import {NB_TRANCHES, LIQUIDATION_BONUS_FACTOR} from "./Constants.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library TrancheIdLib {
    using WadRayMath for uint256;

    function mask(TrancheId trancheId) internal pure returns (uint256) {
        return 1 << TrancheId.unwrap(trancheId);
    }

    function index(TrancheId trancheId) internal pure returns (uint256) {
        return TrancheId.unwrap(trancheId);
    }

    function isValid(TrancheId trancheId) internal pure returns (bool) {
        return TrancheId.unwrap(trancheId) < NB_TRANCHES;
    }

    function isBorrowing(TrancheId trancheId, uint256 tranchesMask) internal pure returns (bool) {
        return mask(trancheId) & tranchesMask != 0;
    }

    function setBorrowing(TrancheId trancheId, uint256 tranchesMask, bool borrowing) internal pure returns (uint256) {
        return (tranchesMask & ~mask(trancheId)) | (uint256(borrowing ? 1 : 0) << TrancheId.unwrap(trancheId));
    }

    /// @dev Return the tranche's liquidation LTV.
    /// TODO: this could be externalized to a configuration contract (same as the IRM to be simpler), defining the tranche spacing, if we are not confident enough on tranche spacing.
    function getLiquidationLtv(TrancheId trancheId) internal pure returns (uint256) {
        return ((TrancheId.unwrap(trancheId) + 1) * WadRayMath.WAD) / NB_TRANCHES;
    }

    /// @dev Returns the liquidation bonus associated to the given tranche, based on its liquidation LTV.
    /// The liquidation bonus is chosen to be decreasing with liquidation LTV and defines a price band large enough
    /// so liquidators are given a margin to liquidate borrowers profitably before their position holds bad debt.
    function getLiquidationBonus(TrancheId trancheId, uint256 seized) internal pure returns (uint256) {
        uint256 liquidationBonusMultiplier =
            LIQUIDATION_BONUS_FACTOR.wadMul(WadRayMath.WAD.wadDiv(getLiquidationLtv(trancheId)) - WadRayMath.WAD);

        return seized.wadMul(liquidationBonusMultiplier);
    }
}
