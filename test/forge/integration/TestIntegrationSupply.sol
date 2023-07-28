// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/forge/BlueBase.t.sol";

contract BlueBaseTest is BlueBaseTest {
    function testSupplyUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert("unknown market");
        blue.supply(marketFuzz, 1, address(this));
    }

    function testSupplyUnknownMarket() public {
        vm.expectRevert("zero amount");
        blue.supply(market, 0, address(this));
    }

    function testSupply(uint256 amount) {}

    function testSupplyOnBehalf(uint256 amount, address onBehalf) {}
}
