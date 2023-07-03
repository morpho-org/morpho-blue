// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

contract ChainlinkAggregatorOracle is IOracle {
    IChainlinkAggregatorV3 internal immutable _FEED;

    uint256 internal immutable _ASSET_UNIT;

    constructor(address feed, uint256 assetUnit) {
        _FEED = IChainlinkAggregatorV3(feed);
        _ASSET_UNIT = assetUnit;
    }

    function price() external view returns (uint256, bool, bool) {
        int256 answer = _FEED.latestAnswer();

        uint256 wad = uint256(answer) * WadRayMath.WAD / _ASSET_UNIT;

        return (wad, true, answer > 0);
    }
}
