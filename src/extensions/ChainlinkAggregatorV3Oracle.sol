// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

contract ChainlinkAggregatorV3Oracle is IOracle {
    IChainlinkAggregatorV3 internal immutable _FEED;

    uint256 internal immutable _ASSET_UNIT;
    uint256 internal immutable _TIMEOUT;

    constructor(address feed, uint256 timeout, uint256 assetUnit) {
        _FEED = IChainlinkAggregatorV3(feed);
        _TIMEOUT = timeout;
        _ASSET_UNIT = assetUnit;
    }

    function price() external view returns (uint256, bool, bool) {
        (, int256 answer,, uint256 updatedAt,) = _FEED.latestRoundData();

        uint256 wad = uint256(answer) * WadRayMath.WAD / _ASSET_UNIT;

        if (block.timestamp > updatedAt + _TIMEOUT) return (wad, false, false);

        return (wad, true, answer > 0);
    }
}
