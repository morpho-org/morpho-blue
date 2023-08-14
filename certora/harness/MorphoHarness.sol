pragma solidity 0.8.19;

import "../../src/Morpho.sol";
import "../../src/libraries/SharesMathLib.sol";

contract MorphoHarness is Morpho {
    constructor(address newOwner) Morpho(newOwner) {}

    function getVirtualTotalSupply(Id id) external view returns (uint256) {
        return totalSupply[id] + SharesMathLib.VIRTUAL_ASSETS;
    }

    function getVirtualTotalSupplyShares(Id id) external view returns (uint256) {
        return totalSupplyShares[id] + SharesMathLib.VIRTUAL_SHARES;
    }

    function getTotalSupply(Id id) external view returns (uint256) {
        return totalSupply[id];
    }

    function getTotalSupplyShares(Id id) external view returns (uint256) {
        return totalSupplyShares[id];
    }

    function getTotalBorrowShares(Id id) external view returns (uint256) {
        return totalBorrowShares[id];
    }
}
