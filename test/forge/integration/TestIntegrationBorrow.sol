// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueBase.t.sol";

contract IntegrationBorrowTest is BlueBaseTest {
    using FixedPointMathLib for uint256;

    function testBorrowUnknownMarket(Market memory marketFuzz, address borrowerFuzz, address receiver, uint256 amount)
        public
    {
        vm.assume(neq(marketFuzz, market) && receiver != address(0));

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.borrow(marketFuzz, amount, borrowerFuzz, receiver);
    }

    function testBorrowZeroAmount(address borrowerFuzz, address receiver) public {
        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.borrow(market, 0, borrowerFuzz, receiver);
    }

    function testBorrowToZeroAddress(address borrowerFuzz, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        _provideLiquidity(amount);

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.borrow(market, amount, borrowerFuzz, address(0));
    }

    function testBorrowUnauthorized(address supplier, address attacker, address receiver, uint256 amount) public {
        vm.assume(supplier != attacker && supplier != address(0) && receiver != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        _provideLiquidity(amount);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(blue), amount);
        blue.supplyCollateral(market, amount, supplier, hex"");
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.borrow(market, amount, supplier, receiver);
    }

    function testBorrowUnhealthyPosition(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundUnhealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testBorrowUnsufficientLiquidity(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, 1, amountBorrowed - 1);
        _provideLiquidity(amountSupplied);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testBorrow(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(blue));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        uint256 expectedBorrowShares = amountBorrowed * SharesMath.VIRTUAL_SHARES;

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Borrow(id, BORROWER, BORROWER, receiver, amountBorrowed, expectedBorrowShares);
        blue.borrow(market, amountBorrowed, BORROWER, receiver);
        vm.stopPrank();

        assertEq(blue.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(blue.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(blue.borrowShares(id, BORROWER), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed, "blue balance");
    }

    function testBorrowOnBehalf(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(blue));
        vm.assume(receiver != address(0) && receiver != address(blue));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(onBehalf, amountCollateral);

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(blue), amountCollateral);
        blue.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        blue.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 expectedBorrowShares = amountBorrowed * SharesMath.VIRTUAL_SHARES;

        vm.prank(BORROWER);
        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Borrow(id, BORROWER, onBehalf, receiver, amountBorrowed, expectedBorrowShares);
        blue.borrow(market, amountBorrowed, onBehalf, receiver);

        assertEq(blue.borrowShares(id, onBehalf), expectedBorrowShares, "borrow shares");
        assertEq(blue.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(blue.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed, "blue balance");
    }
}
