// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../../src/Morpho.sol";
import "../../src/libraries/SharesMathLib.sol";
import "../../src/libraries/MarketParamsLib.sol";

contract MorphoHarness is Morpho {
    using MarketParamsLib for MarketParams;

    constructor(address newOwner) Morpho(newOwner) {}

    function idToMarketParams_(bytes32 id) external view returns (MarketParams memory) {
        return idToMarketParams[id];
    }

    function market_(bytes32 id) external view returns (Market memory) {
        return market[id];
    }

    function position_(bytes32 id, address user) external view returns (Position memory) {
        return position[id][user];
    }

    function totalSupplyAssets(bytes32 id) external view returns (uint256) {
        return market[id].totalSupplyAssets;
    }

    function totalSupplyShares(bytes32 id) external view returns (uint256) {
        return market[id].totalSupplyShares;
    }

    function totalBorrowAssets(bytes32 id) external view returns (uint256) {
        return market[id].totalBorrowAssets;
    }

    function totalBorrowShares(bytes32 id) external view returns (uint256) {
        return market[id].totalBorrowShares;
    }

    function supplyShares(bytes32 id, address account) external view returns (uint256) {
        return position[id][account].supplyShares;
    }

    function borrowShares(bytes32 id, address account) external view returns (uint256) {
        return position[id][account].borrowShares;
    }

    function collateral(bytes32 id, address account) external view returns (uint256) {
        return position[id][account].collateral;
    }

    function lastUpdate(bytes32 id) external view returns (uint256) {
        return market[id].lastUpdate;
    }

    function fee(bytes32 id) external view returns (uint256) {
        return market[id].fee;
    }

    function virtualTotalSupplyAssets(bytes32 id) external view returns (uint256) {
        return market[id].totalSupplyAssets + SharesMathLib.VIRTUAL_ASSETS;
    }

    function virtualTotalSupplyShares(bytes32 id) external view returns (uint256) {
        return market[id].totalSupplyShares + SharesMathLib.VIRTUAL_SHARES;
    }

    function virtualTotalBorrowAssets(bytes32 id) external view returns (uint256) {
        return market[id].totalBorrowAssets + SharesMathLib.VIRTUAL_ASSETS;
    }

    function virtualTotalBorrowShares(bytes32 id) external view returns (uint256) {
        return market[id].totalBorrowShares + SharesMathLib.VIRTUAL_SHARES;
    }

    function isHealthy(MarketParams memory marketParams, address user) external view returns (bool) {
        return _isHealthy(marketParams, marketParams.id(), user);
    }
}
