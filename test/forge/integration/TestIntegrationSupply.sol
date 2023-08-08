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

    function testSupply(address supplier, address onBehalf, uint256 amount) public {
        vm.assume(supplier != address(blue) && onBehalf != address(blue) && onBehalf != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(supplier, amount);

        uint256 expectedSupplyShares = amount * SharesMath.VIRTUAL_SHARES;

        vm.startPrank(supplier);
        borrowableAsset.approve(address(blue), amount);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Supply(id, supplier, onBehalf, amount, expectedSupplyShares);
        blue.supply(market, amount, onBehalf, hex"");
        vm.stopPrank();

        assertEq(blue.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupply(id), amount, "total supply");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableAsset.balanceOf(supplier), 0, "supplier balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }
}
