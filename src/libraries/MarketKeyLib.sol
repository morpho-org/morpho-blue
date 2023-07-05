// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MarketKey} from "./Types.sol";
import {LIQUIDATION_BONUS_FACTOR} from "./Constants.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library MarketKeyLib {
    using WadRayMath for uint256;

    /// @dev Returns the given market's configuration id, so that it uniquely identifies a market in the storage.
    function toId(MarketKey calldata marketKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(marketKey));
    }

    /// @dev Returns the liquidation bonus associated to the given market, based on its liquidation LTV.
    /// The liquidation bonus is chosen to be decreasing with liquidation LTV and defines a price band large enough
    /// so liquidators are given a margin to liquidate borrowers profitably before their position holds bad debt.
    function getLiquidationBonus(MarketKey calldata marketKey, uint256 seized) internal pure returns (uint256) {
        uint256 liquidationBonusMultiplier =
            LIQUIDATION_BONUS_FACTOR.wadMul(WadRayMath.WAD.wadDiv(marketKey.liquidationLtv) - WadRayMath.WAD);

        return seized.wadMul(liquidationBonusMultiplier);
    }
}

library MarketKeyMemLib {
    using WadRayMath for uint256;

    /// @dev Returns the given market's configuration id, so that it uniquely identifies a market in the storage.
    function toId(MarketKey memory marketKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(marketKey));
    }

    /// @dev Returns the liquidation bonus associated to the given market, based on its liquidation LTV.
    /// The liquidation bonus is chosen to be decreasing with liquidation LTV and defines a price band large enough
    /// so liquidators are given a margin to liquidate borrowers profitably before their position holds bad debt.
    function getLiquidationBonus(MarketKey memory marketKey, uint256 seized) internal pure returns (uint256) {
        uint256 liquidationBonusMultiplier =
            LIQUIDATION_BONUS_FACTOR.wadMul(WadRayMath.WAD.wadDiv(marketKey.liquidationLtv) - WadRayMath.WAD);

        return seized.wadMul(liquidationBonusMultiplier);
    }
}
