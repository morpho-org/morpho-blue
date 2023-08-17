pragma solidity 0.8.19;

import "../../src/Morpho.sol";
import "../../src/libraries/SharesMathLib.sol";
import "../../src/libraries/MarketLib.sol";

contract MorphoHarness is Morpho {
    using MarketLib for Market;

    constructor(address newOwner) Morpho(newOwner) {}

    function getVirtualTotalSupply(Id id) external view returns (uint256) {
        return totalSupply[id] + SharesMathLib.VIRTUAL_ASSETS;
    }

    function getVirtualTotalSupplyShares(Id id) external view returns (uint256) {
        return totalSupplyShares[id] + SharesMathLib.VIRTUAL_SHARES;
    }

    function getVirtualTotalBorrow(Id id) external view returns (uint256) {
        return totalBorrow[id] + SharesMathLib.VIRTUAL_ASSETS;
    }

    function getVirtualTotalBorrowShares(Id id) external view returns (uint256) {
        return totalBorrowShares[id] + SharesMathLib.VIRTUAL_SHARES;
    }

    // Setter functions for summarizing accrueInterests
    function setTotalSupply(Id id, uint256 newValue) external {
        totalSupply[id] = newValue;
    }

    function setTotalSupplyShares(Id id, uint256 newValue) external {
        totalSupplyShares[id] = newValue;
    }

    function setTotalBorrow(Id id, uint256 newValue) external {
        totalBorrow[id] = newValue;
    }

    function getMarketId(Market memory market) external pure returns (Id) {
        return market.id();
    }

    function mathLibMulDivUp(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return MathLib.mulDivUp(x, y, d);
    }

    function mathLibMulDivDown(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return MathLib.mulDivDown(x, y, d);
    }
}
