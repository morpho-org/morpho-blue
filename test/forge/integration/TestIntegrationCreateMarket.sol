// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationCreateMarketTest is BlueBaseTest {
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    function testCreateMarketWithNotEnabledIrm(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != irm);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.IRM_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testCreateMarketWithEnabledIrmAndNotEnabledLLTV(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);

        vm.startPrank(OWNER);
        blue.enableIrm(marketFuzz.irm);
        vm.expectRevert(bytes(Errors.LLTV_NOT_ENABLED));
        blue.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndLLTV(Market memory marketFuzz) public {
        marketFuzz.lltv = LLTV;
        Id marketFuzzId = marketFuzz.id();

        vm.prank(OWNER);
        blue.enableIrm(marketFuzz.irm);
        blue.createMarket(marketFuzz);

        assertGt(blue.lastUpdate(marketFuzzId), 0, "creation timestamp");
    }
}
