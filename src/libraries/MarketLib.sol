// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IBlue} from "../interfaces/IBlue.sol";

library MarketLib {
    function id(Market memory market) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(market)));
    }
}
