// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../../src/MorphoBlueReconstruction.sol";

contract MorphoHarness is MorphoBlueReconstruction {
    constructor(address newOwner) MorphoBlueReconstruction(newOwner) {}

    function idToMarketParams_(Id id) external view returns (MarketParams memory) {
        return idToMarketParams[id];
    }

    function market_(Id id) external view returns (Market memory) {
        return market[id];
    }

    function position_(Id id, address user) external view returns (Position memory) {
        return position[id][user];
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
        return market[id].totalSupplyAssets + ReconstructedMath.VIRTUAL_ASSETS;
    }

    function virtualTotalSupplyShares(Id id) external view returns (uint256) {
        return market[id].totalSupplyShares + ReconstructedMath.VIRTUAL_SHARES;
    }

    function virtualTotalBorrowAssets(Id id) external view returns (uint256) {
        return market[id].totalBorrowAssets + ReconstructedMath.VIRTUAL_ASSETS;
    }

    function virtualTotalBorrowShares(Id id) external view returns (uint256) {
        return market[id].totalBorrowShares + ReconstructedMath.VIRTUAL_SHARES;
    }

    function isHealthy(MarketParams memory marketParams, address user) external view returns (bool) {
        return _isHealthy(marketParams, _id(marketParams), user);
    }
}
