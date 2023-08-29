// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract SupplyCollateralIntegrationTest is BaseTest {
    using MorphoLib for Morpho;

    function testSupplyCollateralMarketNotCreated(MarketParams memory marketParamsFuzz, uint256 amount) public {
        vm.assume(neq(marketParamsFuzz, marketParams));

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supplyCollateral(marketParamsFuzz, amount, SUPPLIER, hex"");
    }

    function testSupplyCollateralZeroAmount(address SUPPLIER) public {
        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.supplyCollateral(marketParams, 0, SUPPLIER, hex"");
    }

    function testSupplyCollateralOnBehalfZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supplyCollateral(marketParams, amount, address(0), hex"");
    }

    function testSupplyCollateral(uint256 amount) public {
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.prank(SUPPLIER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.SupplyCollateral(id, SUPPLIER, ONBEHALF, amount);
        morpho.supplyCollateral(marketParams, amount, ONBEHALF, hex"");

        assertEq(morpho.collateral(id, ONBEHALF), amount, "collateral");
        assertEq(collateralToken.balanceOf(SUPPLIER), 0, "SUPPLIER balance");
        assertEq(collateralToken.balanceOf(address(morpho)), amount, "morpho balance");
    }
}
