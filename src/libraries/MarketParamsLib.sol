// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Id, MarketParams} from "../interfaces/IMorpho.sol";

/// @title MarketParamsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to convert a market to its id.
library MarketParamsLib {
    /// @notice Returns the id of the market `marketParams`.
    function id(MarketParams memory marketParams) internal pure returns (Id marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, mul(5, 32))
        }
    }
}
