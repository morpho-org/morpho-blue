// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationSupplyCollateralTest is BaseTest {
    using MorphoLib for Morpho;

    function testSupplyCollateralMarketNotCreated(Market memory marketFuzz, uint256 amount) public {
        vm.assume(neq(marketFuzz, market));

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supplyCollateral(marketFuzz, amount, SUPPLIER, hex"");
    }

    function testSupplyCollateralZeroAmount(address SUPPLIER) public {
        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.supplyCollateral(market, 0, SUPPLIER, hex"");
    }

    function testSupplyCollateralOnBehalfZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supplyCollateral(market, amount, address(0), hex"");
    }

    function testSupplyCollateral(uint256 amount) public {
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.prank(SUPPLIER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.SupplyCollateral(id, SUPPLIER, ONBEHALF, amount);
        morpho.supplyCollateral(market, amount, ONBEHALF, hex"");

        assertEq(morpho.collateral(id, ONBEHALF), amount, "collateral");
        assertEq(collateralToken.balanceOf(SUPPLIER), 0, "SUPPLIER balance");
        assertEq(collateralToken.balanceOf(address(morpho)), amount, "morpho balance");
    }
}
