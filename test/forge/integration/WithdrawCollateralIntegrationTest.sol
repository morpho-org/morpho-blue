// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract WithdrawCollateralIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;

    function testWithdrawCollateralMarketNotCreated(MarketParams memory marketParamsFuzz) public {
        vm.assume(neq(marketParamsFuzz, marketParams));

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdrawCollateral(marketParamsFuzz, 1, SUPPLIER, RECEIVER);
    }

    function testWithdrawCollateralZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.startPrank(SUPPLIER);
        collateralToken.approve(address(morpho), amount);
        morpho.supplyCollateral(marketParams, amount, SUPPLIER, hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.withdrawCollateral(marketParams, 0, SUPPLIER, RECEIVER);
        vm.stopPrank();
    }

    function testWithdrawCollateralToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.startPrank(SUPPLIER);
        morpho.supplyCollateral(marketParams, amount, SUPPLIER, hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdrawCollateral(marketParams, amount, SUPPLIER, address(0));
        vm.stopPrank();
    }

    function testWithdrawCollateralUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != SUPPLIER);
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.prank(SUPPLIER);
        morpho.supplyCollateral(marketParams, amount, SUPPLIER, hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdrawCollateral(marketParams, amount, SUPPLIER, RECEIVER);
    }

    function testWithdrawCollateralUnhealthyPosition(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        morpho.withdrawCollateral(marketParams, amountCollateral, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testWithdrawCollateral(
        uint256 amountCollateral,
        uint256 amountCollateralExcess,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);
        vm.assume(amountCollateral < MAX_COLLATERAL_ASSETS);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        amountCollateralExcess = bound(
            amountCollateralExcess,
            1,
            min(MAX_COLLATERAL_ASSETS - amountCollateral, type(uint256).max / priceCollateral - amountCollateral)
        );

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral + amountCollateralExcess);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral + amountCollateralExcess, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.WithdrawCollateral(id, BORROWER, BORROWER, RECEIVER, amountCollateralExcess);
        morpho.withdrawCollateral(marketParams, amountCollateralExcess, BORROWER, RECEIVER);

        vm.stopPrank();

        assertEq(morpho.collateral(id, BORROWER), amountCollateral, "collateral balance");
        assertEq(collateralToken.balanceOf(RECEIVER), amountCollateralExcess, "lender balance");
        assertEq(collateralToken.balanceOf(address(morpho)), amountCollateral, "morpho balance");
    }

    function testWithdrawCollateralOnBehalf(
        uint256 amountCollateral,
        uint256 amountCollateralExcess,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);
        vm.assume(amountCollateral < MAX_COLLATERAL_ASSETS);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        amountCollateralExcess = bound(
            amountCollateralExcess,
            1,
            min(MAX_COLLATERAL_ASSETS - amountCollateral, type(uint256).max / priceCollateral - amountCollateral)
        );

        collateralToken.setBalance(ONBEHALF, amountCollateral + amountCollateralExcess);

        vm.startPrank(ONBEHALF);
        morpho.supplyCollateral(marketParams, amountCollateral + amountCollateralExcess, ONBEHALF, hex"");
        morpho.setAuthorization(BORROWER, true);
        morpho.borrow(marketParams, amountBorrowed, 0, ONBEHALF, ONBEHALF);
        vm.stopPrank();

        vm.prank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.WithdrawCollateral(id, BORROWER, ONBEHALF, RECEIVER, amountCollateralExcess);
        morpho.withdrawCollateral(marketParams, amountCollateralExcess, ONBEHALF, RECEIVER);

        assertEq(morpho.collateral(id, ONBEHALF), amountCollateral, "collateral balance");
        assertEq(collateralToken.balanceOf(RECEIVER), amountCollateralExcess, "lender balance");
        assertEq(collateralToken.balanceOf(address(morpho)), amountCollateral, "morpho balance");
    }
}
