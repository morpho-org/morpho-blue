// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationSupplyTest is BlueBaseTest {
    function testSupplyUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.supply(marketFuzz, 1, address(this), hex"");
    }

    function testSupplyZeroAmount() public {
        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.supply(market, 0, address(this), hex"");
    }

    function testSupplyOnBehalfZeroAddress() public {
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.supply(market, 1, address(0), hex"");
    }

    function testSupply(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Supply(id, address(this), address(this), amount, amount * SharesMath.VIRTUAL_SHARES);
        blue.supply(market, amount, address(this), hex"");

        assertEq(blue.totalSupply(id), amount, "total supply");
        assertEq(blue.supplyShares(id, address(this)), amount * SharesMath.VIRTUAL_SHARES, "supply shares");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testSupplyOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(blue) && onBehalf != address(0));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Supply(id, address(this), onBehalf, amount, amount * SharesMath.VIRTUAL_SHARES);
        blue.supply(market, amount, onBehalf, hex"");

        assertEq(blue.totalSupply(id), amount, "total supply");
        assertEq(blue.supplyShares(id, onBehalf), amount * SharesMath.VIRTUAL_SHARES, "supply shares");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }
}
