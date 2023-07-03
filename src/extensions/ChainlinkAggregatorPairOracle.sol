// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

contract ChainlinkAggregatorPairOracle is IOracle {
    using WadRayMath for uint256;

    IChainlinkAggregatorV3 internal immutable _COLLATERAL_FEED;
    IChainlinkAggregatorV3 internal immutable _ASSET_FEED;

    uint256 internal immutable _COLLATERAL_UNIT;
    uint256 internal immutable _ASSET_UNIT;

    constructor(address collateralFeed, address assetFeed, uint256 collateralUnit, uint256 assetUnit) {
        _COLLATERAL_FEED = IChainlinkAggregatorV3(collateralFeed);
        _ASSET_FEED = IChainlinkAggregatorV3(assetFeed);
        _COLLATERAL_UNIT = collateralUnit;
        _ASSET_UNIT = assetUnit;
    }

    function price() external view returns (uint256, bool, bool) {
        int256 collateralAnswer = _COLLATERAL_FEED.latestAnswer();
        int256 assetAnswer = _ASSET_FEED.latestAnswer();

        bool isAssetValid = assetAnswer > 0;
        uint256 wad = (uint256(collateralAnswer) * _ASSET_UNIT).wadDiv(uint256(assetAnswer) * _COLLATERAL_UNIT);

        return (wad, isAssetValid, collateralAnswer > 0);
    }
}
