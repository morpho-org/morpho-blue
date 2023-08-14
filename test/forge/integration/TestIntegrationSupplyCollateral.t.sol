// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationSupplyCollateralTest is BaseTest {
    function testSupplyCollateralMarketNotCreated(Market memory marketFuzz, address supplier, uint256 amount) public {
        vm.assume(neq(marketFuzz, market) && supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supply(marketFuzz, amount, 0, supplier, hex"");
    }

    function testSupplyCollateralZeroAmount(address supplier) public {
        vm.assume(supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.supplyCollateral(market, 0, supplier, hex"");
    }

    function testSupplyCollateralOnBehalfZeroAddress(address supplier, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supplyCollateral(market, amount, address(0), hex"");
    }

    function testSupplyCollateral(address supplier, address onBehalf, uint256 amount) public {
        vm.assume(
            supplier != address(morpho) && supplier != address(0) && onBehalf != address(morpho)
                && onBehalf != address(0)
        );
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralToken.approve(address(morpho), amount);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.SupplyCollateral(id, supplier, onBehalf, amount);
        morpho.supplyCollateral(market, amount, onBehalf, hex"");
        vm.stopPrank();

        assertEq(morpho.collateral(id, onBehalf), amount, "collateral");
        assertEq(collateralToken.balanceOf(supplier), 0, "supplier balance");
        assertEq(collateralToken.balanceOf(address(morpho)), amount, "morpho balance");
    }
}
