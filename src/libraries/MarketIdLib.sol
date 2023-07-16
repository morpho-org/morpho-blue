// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Market} from "src/libraries/Types.sol";

// Market id.
type Id is bytes32;

library MarketIdLib {
    function toId(Market calldata market) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(market)));
    }
}
