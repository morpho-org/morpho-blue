// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueBase.t.sol";

contract IntegrationCreateMarketTest is BlueBaseTest {
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    function testCreateMarketWithNotEnabledIrmAndNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != address(irm) && marketFuzz.lltv != LLTV);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.IRM_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testCreateMarketWithNotEnabledIrmAndEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != address(irm));
        marketFuzz.lltv = _boundValidLltv(marketFuzz.lltv);

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.EnableLltv(marketFuzz.lltv);
        blue.enableLltv(marketFuzz.lltv);

        vm.expectRevert(bytes(Errors.IRM_NOT_ENABLED));
        blue.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.EnableIrm(marketFuzz.irm);
        blue.enableIrm(marketFuzz.irm);

        vm.expectRevert(bytes(Errors.LLTV_NOT_ENABLED));
        blue.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndLltv(Market memory marketFuzz) public {
        marketFuzz.lltv = LLTV;
        Id marketFuzzId = marketFuzz.id();

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.EnableIrm(marketFuzz.irm);
        blue.enableIrm(marketFuzz.irm);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.CreateMarket(marketFuzz.id(), marketFuzz);
        blue.createMarket(marketFuzz);

        assertEq(blue.lastUpdate(marketFuzzId), block.timestamp, "lastUpdate != block.timestamp");
        assertEq(blue.totalSupply(marketFuzzId), 0, "totalSupply != 0");
        assertEq(blue.totalSupplyShares(marketFuzzId), 0, "totalSupplyShares != 0");
        assertEq(blue.totalBorrow(marketFuzzId), 0, "totalBorrow != 0");
        assertEq(blue.totalBorrowShares(marketFuzzId), 0, "totalBorrowShares != 0");
        assertEq(blue.fee(marketFuzzId), 0, "fee != 0");
    }
}
