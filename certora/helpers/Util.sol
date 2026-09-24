// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../../src/MorphoBlueReconstruction.sol";

contract Util {
    using ReconstructedMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
    uint256 internal constant MAX_FEE = 0.25e18;
    uint256 internal constant LIQUIDATION_CURSOR = 0.3e18;
    uint256 internal constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    function wad() external pure returns (uint256) {
        return WAD;
    }

    function maxFee() external pure returns (uint256) {
        return MAX_FEE;
    }

    function oraclePriceScale() external pure returns (uint256) {
        return ORACLE_PRICE_SCALE;
    }

    function lif(uint256 lltv) external pure returns (uint256) {
        return ReconstructedMath.min(
            MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv))
        );
    }

    // The reconstruction has no MarketParamsLib; `_id` is an internal contract function computing this.
    function libId(MarketParams memory marketParams) external pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams)));
    }

    function refId(MarketParams memory marketParams) external pure returns (Id marketParamsId) {
        marketParamsId = Id.wrap(keccak256(abi.encode(marketParams)));
    }

    function libMulDivUp(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return ReconstructedMath.mulDivUp(x, y, d);
    }

    function libMulDivDown(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return ReconstructedMath.mulDivDown(x, y, d);
    }

    function libMin(uint256 x, uint256 y) external pure returns (uint256) {
        return ReconstructedMath.min(x, y);
    }
}
