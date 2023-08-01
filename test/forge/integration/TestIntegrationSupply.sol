// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationSupplyTest is BlueBaseTest {
    function testSupplyUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert("market not created");
        blue.supply(marketFuzz, 1, address(this), hex"");
    }

    function testSupplyZeroAmount() public {
        vm.expectRevert("zero amount");
        blue.supply(market, 0, address(this), hex"");
    }

    function testSupply(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        assertEq(blue.totalSupply(id), amount, "total supply");
        assertEq(blue.supplyShare(id, address(this)), amount * SharesMath.VIRTUAL_SHARES, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testSupplyOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, onBehalf, hex"");

        assertEq(blue.totalSupply(id), amount, "total supply");
        assertEq(blue.supplyShare(id, onBehalf), amount * SharesMath.VIRTUAL_SHARES, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }
}
