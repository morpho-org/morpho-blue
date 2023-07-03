// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MarketKey} from "src/libraries/Types.sol";

library MarketKeyLib {
    /// @dev Returns the given market's configuration id, so that it uniquely identifies a market in the storage.
    function toId(MarketKey calldata marketKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(marketKey));
    }
}
