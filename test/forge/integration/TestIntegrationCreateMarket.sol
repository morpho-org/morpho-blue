// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationCreateMarketTest is BlueBaseTest {
    function testCreateMarketWithNotEnabledIrm(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != irm);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.IRM_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }
}