// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Id, MarketParams} from "../interfaces/IMorpho.sol";

/// @title MarketParamsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to convert a market to its id.
library MarketParamsLib {
    /// @notice Returns the id of the market `marketParams`.
    function id(MarketParams memory marketParams) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams)));
    }
}
