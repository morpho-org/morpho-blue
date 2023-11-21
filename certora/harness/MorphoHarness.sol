// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../../src/Morpho.sol";
import "../../src/libraries/SharesMathLib.sol";
import "../../src/libraries/MarketParamsLib.sol";

contract MorphoHarness is Morpho {
    using MarketParamsLib for MarketParams;

    constructor(address newOwner) Morpho(newOwner) {}

    function wad() external pure returns (uint256) {
        return WAD;
    }

    function maxFee() external pure returns (uint256) {
        return MAX_FEE;
    }

    function totalSupplyAssets(Id id) external view returns (uint256) {
        return market[id].totalSupplyAssets;
    }

    function totalSupplyShares(Id id) external view returns (uint256) {
        return market[id].totalSupplyShares;
    }

    function totalBorrowAssets(Id id) external view returns (uint256) {
        return market[id].totalBorrowAssets;
    }

    function totalBorrowShares(Id id) external view returns (uint256) {
        return market[id].totalBorrowShares;
    }

    function supplyShares(Id id, address account) external view returns (uint256) {
        return position[id][account].supplyShares;
    }

    function borrowShares(Id id, address account) external view returns (uint256) {
        return position[id][account].borrowShares;
    }

    function collateral(Id id, address account) external view returns (uint256) {
        return position[id][account].collateral;
    }

    function lastUpdate(Id id) external view returns (uint256) {
        return market[id].lastUpdate;
    }

    function fee(Id id) external view returns (uint256) {
        return market[id].fee;
    }

    function virtualTotalSupplyAssets(Id id) external view returns (uint256) {
        return market[id].totalSupplyAssets + SharesMathLib.VIRTUAL_ASSETS;
    }

    function virtualTotalSupplyShares(Id id) external view returns (uint256) {
        return market[id].totalSupplyShares + SharesMathLib.VIRTUAL_SHARES;
    }

    function virtualTotalBorrowAssets(Id id) external view returns (uint256) {
        return market[id].totalBorrowAssets + SharesMathLib.VIRTUAL_ASSETS;
    }

    function virtualTotalBorrowShares(Id id) external view returns (uint256) {
        return market[id].totalBorrowShares + SharesMathLib.VIRTUAL_SHARES;
    }

    function libId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }

    function refId(MarketParams memory marketParams) external pure returns (Id marketParamsId) {
        marketParamsId = Id.wrap(keccak256(abi.encode(marketParams)));
    }

    function libMulDivUp(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return MathLib.mulDivUp(x, y, d);
    }

    function libMulDivDown(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return MathLib.mulDivDown(x, y, d);
    }

    function isHealthy(MarketParams memory marketParams, address user) external view returns (bool) {
        return _isHealthy(marketParams, marketParams.id(), user);
    }
}
