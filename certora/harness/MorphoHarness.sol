pragma solidity 0.8.19;

import "../munged/Morpho.sol";
import "../munged/libraries/SharesMathLib.sol";
import "../munged/libraries/MarketParamsLib.sol";

contract MorphoHarness is Morpho {
    using MarketParamsLib for MarketParams;

    constructor(address newOwner) Morpho(newOwner) {}

    function WAD() external pure returns (uint256) {
        return WAD;
    }

    function VIRTUAL_SHARES() external pure returns (uint256) {
        return SharesMathLib.VIRTUAL_SHARES;
    }

    function VIRTUAL_ASSETS() external pure returns (uint256) {
        return SharesMathLib.VIRTUAL_ASSETS;
    }

    function MAX_FEE() external pure returns (uint256) {
        return MAX_FEE;
    }

    function getTotalSupplyAssets(Id id) external view returns (uint256) {
        return market[id].totalSupplyAssets;
    }

    function getTotalSupplyShares(Id id) external view returns (uint256) {
        return market[id].totalSupplyShares;
    }

    function getTotalBorrowAssets(Id id) external view returns (uint256) {
        return market[id].totalBorrowAssets;
    }

    function getTotalBorrowShares(Id id) external view returns (uint256) {
        return market[id].totalBorrowShares;
    }

    function getSupplyShares(Id id, address account) external view returns (uint256) {
        return position[id][account].supplyShares;
    }

    function getBorrowShares(Id id, address account) external view returns (uint256) {
        return position[id][account].borrowShares;
    }

    function getCollateral(Id id, address account) external view returns (uint256) {
        return position[id][account].collateral;
    }

    function getLastUpdate(Id id) external view returns (uint256) {
        return market[id].lastUpdate;
    }

    function getFee(Id id) external view returns (uint256) {
        return market[id].fee;
    }

    function getVirtualTotalSupplyAssets(Id id) external view returns (uint256) {
        return market[id].totalSupplyAssets + SharesMathLib.VIRTUAL_ASSETS;
    }

    function getVirtualTotalSupplyShares(Id id) external view returns (uint256) {
        return market[id].totalSupplyShares + SharesMathLib.VIRTUAL_SHARES;
    }

    function getVirtualTotalBorrowAssets(Id id) external view returns (uint256) {
        return market[id].totalBorrowAssets + SharesMathLib.VIRTUAL_ASSETS;
    }

    function getVirtualTotalBorrowShares(Id id) external view returns (uint256) {
        return market[id].totalBorrowShares + SharesMathLib.VIRTUAL_SHARES;
    }

    function getMarketId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }

    function marketLibId(MarketParams memory marketParams) external pure returns (Id marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, mul(5, 32))
        }
    }

    function mathLibMulDivUp(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return MathLib.mulDivUp(x, y, d);
    }

    function mathLibMulDivDown(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return MathLib.mulDivDown(x, y, d);
    }

    function accrueInterest(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);

        _accrueInterest(marketParams, id);
    }

    function isHealthy(MarketParams memory marketParams, address user) external view returns (bool) {
        return _isHealthy(marketParams, marketParams.id(), user);
    }
}
