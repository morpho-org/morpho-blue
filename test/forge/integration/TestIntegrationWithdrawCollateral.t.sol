// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationWithdrawCollateralTest is BaseTest {
    using MathLib for uint256;

    function testWithdrawCollateralMarketNotCreated(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdrawCollateral(marketFuzz, 1, SUPPLIER, RECEIVER);
    }

    function testWithdrawCollateralZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.startPrank(SUPPLIER);
        collateralToken.approve(address(morpho), amount);
        morpho.supplyCollateral(market, amount, SUPPLIER, hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.withdrawCollateral(market, 0, SUPPLIER, RECEIVER);
        vm.stopPrank();
    }

    function testWithdrawCollateralToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.startPrank(SUPPLIER);
        morpho.supplyCollateral(market, amount, SUPPLIER, hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdrawCollateral(market, amount, SUPPLIER, address(0));
        vm.stopPrank();
    }

    function testWithdrawCollateralUnauthorized(address attacker, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(SUPPLIER, amount);

        vm.prank(SUPPLIER);
        morpho.supplyCollateral(market, amount, SUPPLIER, hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdrawCollateral(market, amount, SUPPLIER, RECEIVER);
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
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        morpho.withdrawCollateral(market, amountCollateral, BORROWER, BORROWER);
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

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        amountCollateralExcess = bound(amountCollateralExcess, 1, MAX_TEST_AMOUNT);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral + amountCollateralExcess);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral + amountCollateralExcess, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.WithdrawCollateral(id, BORROWER, BORROWER, RECEIVER, amountCollateralExcess);
        morpho.withdrawCollateral(market, amountCollateralExcess, BORROWER, RECEIVER);

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

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        amountCollateralExcess = bound(amountCollateralExcess, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(ONBEHALF, amountCollateral + amountCollateralExcess);

        vm.startPrank(ONBEHALF);
        morpho.supplyCollateral(market, amountCollateral + amountCollateralExcess, ONBEHALF, hex"");
        morpho.setAuthorization(BORROWER, true);
        morpho.borrow(market, amountBorrowed, 0, ONBEHALF, ONBEHALF);
        vm.stopPrank();

        vm.prank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.WithdrawCollateral(id, BORROWER, ONBEHALF, RECEIVER, amountCollateralExcess);
        morpho.withdrawCollateral(market, amountCollateralExcess, ONBEHALF, RECEIVER);

        assertEq(morpho.collateral(id, ONBEHALF), amountCollateral, "collateral balance");
        assertEq(collateralToken.balanceOf(RECEIVER), amountCollateralExcess, "lender balance");
        assertEq(collateralToken.balanceOf(address(morpho)), amountCollateral, "morpho balance");
    }
}
