// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IChainlinkAggregatorV3} from "./interfaces/IChainlinkAggregatorV3.sol";

import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

contract ChainlinkAggregatorOracle is IOracle {
    using FixedPointMathLib for uint256;

    IChainlinkAggregatorV3 internal immutable _FEED;

    uint256 internal immutable _PRICE_UNIT;

    constructor(address feed, uint256 assetUnit) {
        _FEED = IChainlinkAggregatorV3(feed);
        _PRICE_UNIT = assetUnit;
    }

    function price() external view returns (uint256, bool, bool) {
        int256 answer = _FEED.latestAnswer();

        uint256 wad = uint256(answer).mulWadDown(_PRICE_UNIT);

        return (wad, true, answer > 0);
    }
}
