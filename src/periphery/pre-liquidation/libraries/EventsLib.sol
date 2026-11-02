// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id} from "../../../interfaces/IMorpho.sol";
import {PreLiquidationParams} from "../interfaces/IPreLiquidation.sol";

/// @title EventsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing events.
library EventsLib {
    /// @dev This event is emitted after calling `onPreLiquidate` which can tamper with the order of events.
    event PreLiquidate(
        Id indexed id,
        address indexed liquidator,
        address indexed borrower,
        uint256 repaidAssets,
        uint256 repaidShares,
        uint256 seizedAssets
    );

    event CreatePreLiquidation(address indexed preLiquidation, Id id, PreLiquidationParams preLiquidationParams);
}
