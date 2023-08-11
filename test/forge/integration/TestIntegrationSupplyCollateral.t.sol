// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationSupplyCollateralTest is BaseTest {
    function testSupplyCollateralMarketNotCreated(Market memory marketFuzz, address supplier, uint256 amount) public {
        vm.assume(neq(marketFuzz, market) && supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.supply(marketFuzz, amount, 0, supplier, hex"");
    }

    function testSupplyCollateralZeroAmount(address supplier) public {
        vm.assume(supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        blue.supplyCollateral(market, 0, supplier, hex"");
    }

    function testSupplyCollateralOnBehalfZeroAddress(address supplier, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.supplyCollateral(market, amount, address(0), hex"");
    }

    function testSupplyCollateral(address supplier, address onBehalf, uint256 amount) public {
        vm.assume(supplier != address(blue) && onBehalf != address(blue) && onBehalf != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(blue), amount);

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.SupplyCollateral(id, supplier, onBehalf, amount);
        blue.supplyCollateral(market, amount, onBehalf, hex"");
        vm.stopPrank();

        assertEq(blue.collateral(id, onBehalf), amount, "collateral");
        assertEq(collateralAsset.balanceOf(supplier), 0, "supplier balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
    }
}
