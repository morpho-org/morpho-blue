// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationCreateMarketTest is BaseTest {
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    function testCreateMarketWithNotEnabledIrmAndNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != address(irm) && marketFuzz.lltv != LLTV);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
    }

    function testCreateMarketWithNotEnabledIrmAndEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != address(irm));
        marketFuzz.lltv = _boundValidLltv(marketFuzz.lltv);

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.EnableLltv(marketFuzz.lltv);
        morpho.enableLltv(marketFuzz.lltv);

        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.EnableIrm(marketFuzz.irm);
        morpho.enableIrm(marketFuzz.irm);

        vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndLltv(Market memory marketFuzz) public {
        marketFuzz.lltv = LLTV;
        Id marketFuzzId = marketFuzz.id();

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.EnableIrm(marketFuzz.irm);
        morpho.enableIrm(marketFuzz.irm);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.CreateMarket(marketFuzz.id(), marketFuzz);
        morpho.createMarket(marketFuzz);

        assertEq(morpho.lastUpdate(marketFuzzId), block.timestamp, "lastUpdate != block.timestamp");
        assertEq(morpho.totalSupply(marketFuzzId), 0, "totalSupply != 0");
        assertEq(morpho.totalSupplyShares(marketFuzzId), 0, "totalSupplyShares != 0");
        assertEq(morpho.totalBorrow(marketFuzzId), 0, "totalBorrow != 0");
        assertEq(morpho.totalBorrowShares(marketFuzzId), 0, "totalBorrowShares != 0");
        assertEq(morpho.fee(marketFuzzId), 0, "fee != 0");
    }
}
