// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

contract ChainlinkAggregatorV3PairOracle is IOracle {
    using WadRayMath for uint256;

    IChainlinkAggregatorV3 internal immutable _COLLATERAL_FEED;
    IChainlinkAggregatorV3 internal immutable _ASSET_FEED;

    uint256 internal immutable _COLLATERAL_UNIT;
    uint256 internal immutable _ASSET_UNIT;
    uint256 internal immutable _TIMEOUT;

    constructor(address collateralFeed, address assetFeed, uint256 timeout, uint256 collateralUnit, uint256 assetUnit) {
        _COLLATERAL_FEED = IChainlinkAggregatorV3(collateralFeed);
        _ASSET_FEED = IChainlinkAggregatorV3(assetFeed);
        _COLLATERAL_UNIT = collateralUnit;
        _ASSET_UNIT = assetUnit;
        _TIMEOUT = timeout;
    }

    function price() external view returns (uint256, bool, bool) {
        (, int256 collateralAnswer,, uint256 collateralUpdatedAt,) = _COLLATERAL_FEED.latestRoundData();
        (, int256 assetAnswer,, uint256 assetUpdatedAt,) = _ASSET_FEED.latestRoundData();

        uint256 wad = (uint256(collateralAnswer) * _ASSET_UNIT).wadDiv(uint256(assetAnswer) * _COLLATERAL_UNIT);

        if (block.timestamp > collateralUpdatedAt + _TIMEOUT || block.timestamp > assetUpdatedAt + _TIMEOUT) {
            return (wad, false, false);
        }

        return (wad, assetAnswer > 0, collateralAnswer > 0);
    }
}
