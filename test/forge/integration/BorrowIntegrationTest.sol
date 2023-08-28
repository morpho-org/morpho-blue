// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract BorrowIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testBorrowMarketNotCreated(MarketParams memory marketParamsFuzz, address borrowerFuzz, uint256 amount)
        public
    {
        vm.assume(neq(marketParamsFuzz, marketParams));

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.borrow(marketParamsFuzz, amount, 0, borrowerFuzz, RECEIVER);
    }

    function testBorrowZeroAmount(address borrowerFuzz) public {
        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.borrow(marketParams, 0, 0, borrowerFuzz, RECEIVER);
    }

    function testBorrowInconsistentInput(address borrowerFuzz, uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.borrow(marketParams, amount, shares, borrowerFuzz, RECEIVER);
    }

    function testBorrowToZeroAddress(address borrowerFuzz, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        _supply(amount);

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.borrow(marketParams, amount, 0, borrowerFuzz, address(0));
    }

    function testBorrowUnauthorized(address supplier, address attacker, uint256 amount) public {
        vm.assume(supplier != attacker && supplier != address(0));
        (uint256 amountCollateral, uint256 amountBorrowed,) = _boundHealthyPosition(amount, amount, ORACLE_PRICE_SCALE);

        _supply(amountBorrowed);

        collateralToken.setBalance(supplier, amountCollateral);

        vm.startPrank(supplier);
        collateralToken.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(marketParams, amountCollateral, supplier, hex"");
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.borrow(marketParams, amountBorrowed, 0, supplier, RECEIVER);
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
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
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
        vm.assume(amountBorrowed >= 2);
        amountSupplied = bound(amountSupplied, 1, amountBorrowed - 1);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testBorrowAssets(
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

        uint256 expectedBorrowShares = amountBorrowed.toSharesUp(0, 0);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, BORROWER, RECEIVER, amountBorrowed, expectedBorrowShares);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, RECEIVER);
        vm.stopPrank();

        assertEq(returnAssets, amountBorrowed, "returned asset amount");
        assertEq(returnShares, expectedBorrowShares, "returned shares amount");
        assertEq(morpho.totalBorrowAssets(id), amountBorrowed, "total borrow");
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), amountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(address(morpho)), amountSupplied - amountBorrowed, "morpho balance");
    }

    function testBorrowShares(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 sharesBorrowed,
        uint256 priceCollateral
    ) public {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        sharesBorrowed = bound(sharesBorrowed, MIN_TEST_SHARES, MAX_TEST_SHARES);
        uint256 expectedAmountBorrowed = sharesBorrowed.toAssetsDown(0, 0);
        uint256 expectedBorrowedValue = sharesBorrowed.toAssetsUp(expectedAmountBorrowed, sharesBorrowed);
        uint256 minCollateral =
            expectedBorrowedValue.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, priceCollateral);
        vm.assume(minCollateral <= MAX_COLLATERAL_ASSETS);
        amountCollateral = bound(amountCollateral, minCollateral, MAX_COLLATERAL_ASSETS);
        vm.assume(amountCollateral <= type(uint256).max / priceCollateral);

        amountSupplied = bound(amountSupplied, expectedAmountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, BORROWER, RECEIVER, expectedAmountBorrowed, sharesBorrowed);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.borrow(marketParams, 0, sharesBorrowed, BORROWER, RECEIVER);
        vm.stopPrank();

        assertEq(returnAssets, expectedAmountBorrowed, "returned asset amount");
        assertEq(returnShares, sharesBorrowed, "returned shares amount");
        assertEq(morpho.totalBorrowAssets(id), expectedAmountBorrowed, "total borrow");
        assertEq(morpho.borrowShares(id, BORROWER), sharesBorrowed, "borrow shares");
        assertEq(morpho.borrowShares(id, BORROWER), sharesBorrowed, "total borrow shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), expectedAmountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(address(morpho)), amountSupplied - expectedAmountBorrowed, "morpho balance");
    }

    function testBorrowAssetsOnBehalf(
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

        collateralToken.setBalance(ONBEHALF, amountCollateral);

        vm.startPrank(ONBEHALF);
        collateralToken.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(marketParams, amountCollateral, ONBEHALF, hex"");
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 expectedBorrowShares = amountBorrowed.toSharesUp(0, 0);

        vm.prank(BORROWER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, ONBEHALF, RECEIVER, amountBorrowed, expectedBorrowShares);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.borrow(marketParams, amountBorrowed, 0, ONBEHALF, RECEIVER);

        assertEq(returnAssets, amountBorrowed, "returned asset amount");
        assertEq(returnShares, expectedBorrowShares, "returned shares amount");
        assertEq(morpho.borrowShares(id, ONBEHALF), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrowAssets(id), amountBorrowed, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), amountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(address(morpho)), amountSupplied - amountBorrowed, "morpho balance");
    }

    function testBorrowSharesOnBehalf(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 sharesBorrowed,
        uint256 priceCollateral
    ) public {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        sharesBorrowed = bound(sharesBorrowed, MIN_TEST_SHARES, MAX_TEST_SHARES);
        uint256 expectedAmountBorrowed = sharesBorrowed.toAssetsDown(0, 0);
        uint256 expectedBorrowedValue = sharesBorrowed.toAssetsUp(expectedAmountBorrowed, sharesBorrowed);
        uint256 minCollateral =
            expectedBorrowedValue.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, priceCollateral);
        vm.assume(minCollateral <= MAX_COLLATERAL_ASSETS);
        amountCollateral = bound(amountCollateral, minCollateral, MAX_COLLATERAL_ASSETS);
        vm.assume(amountCollateral <= type(uint256).max / priceCollateral);

        amountSupplied = bound(amountSupplied, expectedAmountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(ONBEHALF, amountCollateral);

        vm.startPrank(ONBEHALF);
        collateralToken.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(marketParams, amountCollateral, ONBEHALF, hex"");
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        vm.prank(BORROWER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, ONBEHALF, RECEIVER, expectedAmountBorrowed, sharesBorrowed);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.borrow(marketParams, 0, sharesBorrowed, ONBEHALF, RECEIVER);

        assertEq(returnAssets, expectedAmountBorrowed, "returned asset amount");
        assertEq(returnShares, sharesBorrowed, "returned shares amount");
        assertEq(morpho.borrowShares(id, ONBEHALF), sharesBorrowed, "borrow shares");
        assertEq(morpho.totalBorrowAssets(id), expectedAmountBorrowed, "total borrow");
        assertEq(morpho.totalBorrowShares(id), sharesBorrowed, "total borrow shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), expectedAmountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(address(morpho)), amountSupplied - expectedAmountBorrowed, "morpho balance");
    }
}
