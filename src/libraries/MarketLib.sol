// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "../interfaces/IIrm.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";

type Id is bytes32;

struct Market {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    IIrm irm;
    uint256 lltv;
}

library MarketLib {
    function id(Market memory market) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(market)));
    }
}
