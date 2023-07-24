// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IChainlinkAggregatorV3} from "./interfaces/IChainlinkAggregatorV3.sol";

import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

contract ChainlinkAggregatorV3Oracle is IOracle {
    using FixedPointMathLib for uint256;

    IChainlinkAggregatorV3 internal immutable _FEED;

    uint256 internal immutable _PRICE_UNIT;
    uint256 internal immutable _TIMEOUT;

    constructor(address feed, uint256 timeout, uint256 assetUnit) {
        _FEED = IChainlinkAggregatorV3(feed);
        _TIMEOUT = timeout;
        _PRICE_UNIT = assetUnit;
    }

    function price() external view returns (uint256, bool, bool) {
        (, int256 answer,, uint256 updatedAt,) = _FEED.latestRoundData();

        uint256 wad = uint256(answer).mulWadDown(_PRICE_UNIT);

        if (block.timestamp > updatedAt + _TIMEOUT) return (wad, false, false);

        return (wad, true, answer > 0);
    }
}
