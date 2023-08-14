pragma solidity 0.8.19;

import "../../src/Morpho.sol";
import "../../src/libraries/SharesMathLib.sol";

contract MorphoHarness is Morpho {
    using MarketLib for Market;
    
    constructor(address newOwner) Morpho(newOwner) {}

    function getVirtualTotalSupply(Id id) external view returns (uint256) {
        return totalSupply[id] + SharesMathLib.VIRTUAL_ASSETS;
    }

    function getVirtualTotalSupplyShares(Id id) external view returns (uint256) {
        return totalSupplyShares[id] + SharesMathLib.VIRTUAL_SHARES;
    }

    function getMarketId(Market memory market) external pure returns (Id) {
        return market.id();
    }
}
