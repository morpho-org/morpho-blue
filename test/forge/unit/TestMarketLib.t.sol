// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Market, Id} from "src/interfaces/IBlue.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";

contract UnitMarketLibTest is Test {
    using MarketLib for Market;

    function testMarketIdWithDifferentBorrowableAsset(Market memory market, address newBorrowableAsset) public {
        vm.assume(market.borrowableAsset != newBorrowableAsset);
        Id oldId = market.id();
        market.borrowableAsset = newBorrowableAsset;
        Id newId = market.id();
        assertNotEq(Id.unwrap(oldId), Id.unwrap(newId));
    }

    function testMarketIdWithDifferentCollateralAsset(Market memory market, address newCollateralAsset) public {
        vm.assume(market.collateralAsset != newCollateralAsset);
        Id oldId = market.id();
        market.collateralAsset = newCollateralAsset;
        Id newId = market.id();
        assertNotEq(Id.unwrap(oldId), Id.unwrap(newId));
    }

    function testMarketIdWithDifferentOracle(Market memory market, address newOracle) public {
        vm.assume(market.oracle != newOracle);
        Id oldId = market.id();
        market.oracle = newOracle;
        Id newId = market.id();
        assertNotEq(Id.unwrap(oldId), Id.unwrap(newId));
    }

    function testMarketIdWithDifferentIrm(Market memory market, address newIrm) public {
        vm.assume(market.irm != newIrm);
        Id oldId = market.id();
        market.irm = newIrm;
        Id newId = market.id();
        assertNotEq(Id.unwrap(oldId), Id.unwrap(newId));
    }

    function testMarketIdWithDifferentLltv(Market memory market, uint256 newLltv) public {
        vm.assume(market.lltv != newLltv);
        Id oldId = market.id();
        market.lltv = newLltv;
        Id newId = market.id();
        assertNotEq(Id.unwrap(oldId), Id.unwrap(newId));
    }
}
