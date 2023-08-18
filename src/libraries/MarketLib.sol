// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Info} from "../interfaces/IMorpho.sol";

/// @title MarketLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to convert a market to its id.
library MarketLib {
    /// @notice Returns the id of a `market`.
    function id(Info memory info) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(info)));
    }
}
