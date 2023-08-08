// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationSupplyCollateralTest is BlueBaseTest {
    function testSupplyCollateralUnknownMarket(Market memory marketFuzz, address supplier, uint256 amount) public {
        vm.assume(neq(marketFuzz, market) && supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.supply(marketFuzz, amount, supplier, hex"");
    }

    function testSupplyCollateralZeroAmount(address supplier) public {
        vm.assume(supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.supplyCollateral(market, 0, supplier, hex"");
    }

    function testSupplyCollateralOnBehalfZeroAddress(address supplier, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(supplier);
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.supplyCollateral(market, amount, address(0), hex"");
    }

    function testSupplyCollateral(address supplier, address onBehalf, uint256 amount) public {
        vm.assume(supplier != address(blue) && onBehalf != address(blue) && onBehalf != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(blue), amount);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.SupplyCollateral(id, supplier, onBehalf, amount);
        blue.supplyCollateral(market, amount, onBehalf, hex"");
        vm.stopPrank();

        assertEq(blue.collateral(id, onBehalf), amount, "collateral");
        assertEq(collateralAsset.balanceOf(supplier), 0, "supplier balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
    }
}
