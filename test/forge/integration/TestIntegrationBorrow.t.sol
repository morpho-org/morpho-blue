// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationBorrowTest is BaseTest {
    using MathLib for uint256;

    function testBorrowMarketNotCreated(
        Market memory marketFuzz,
        address borrowerFuzz,
        address receiver,
        uint256 amount
    ) public {
        vm.assume(neq(marketFuzz, market) && receiver != address(0));

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.borrow(marketFuzz, amount, 0, borrowerFuzz, receiver);
    }

    function testBorrowZeroAmount(address borrowerFuzz, address receiver) public {
        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.borrow(market, 0, 0, borrowerFuzz, receiver);
    }

    function testBorrowInconsistentInput(address borrowerFuzz, uint256 amount, uint256 shares, address receiver)
        public
    {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.borrow(market, amount, shares, borrowerFuzz, receiver);
    }

    function testBorrowToZeroAddress(address borrowerFuzz, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        _provideLiquidity(amount);

        vm.prank(borrowerFuzz);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.borrow(market, amount, 0, borrowerFuzz, address(0));
    }

    function testBorrowUnauthorized(address supplier, address attacker, address receiver, uint256 amount) public {
        vm.assume(supplier != attacker && supplier != address(0) && receiver != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        _provideLiquidity(amount);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(morpho), amount);
        morpho.supplyCollateral(market, amount, supplier, hex"");
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.borrow(market, amount, 0, supplier, receiver);
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

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
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

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testBorrowAssets(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(morpho));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        uint256 expectedBorrowShares = amountBorrowed * SharesMathLib.VIRTUAL_SHARES;

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, BORROWER, receiver, amountBorrowed, expectedBorrowShares);
        morpho.borrow(market, amountBorrowed, 0, BORROWER, receiver);
        vm.stopPrank();

        assertEq(morpho.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountSupplied - amountBorrowed, "morpho balance");
    }

    function testBorrowShares(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 sharesBorrowed,
        uint256 priceCollateral,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(morpho));

        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        sharesBorrowed = bound(sharesBorrowed, MIN_TEST_SHARES, MAX_TEST_SHARES);
        uint256 expectedAmountBorrowed = sharesBorrowed.mulDivDown(1, SharesMathLib.VIRTUAL_SHARES);

        uint256 expectedBorrowedValue =
            sharesBorrowed.mulDivUp(expectedAmountBorrowed + 1, sharesBorrowed + SharesMathLib.VIRTUAL_SHARES);
        uint256 minCollateral = expectedBorrowedValue.wDivUp(market.lltv).mulDivUp(ORACLE_PRICE_SCALE, priceCollateral);
        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, MAX_TEST_AMOUNT));

        amountSupplied = bound(amountSupplied, expectedAmountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, BORROWER, receiver, expectedAmountBorrowed, sharesBorrowed);
        morpho.borrow(market, 0, sharesBorrowed, BORROWER, receiver);
        vm.stopPrank();

        assertEq(morpho.totalBorrow(id), expectedAmountBorrowed, "total borrow");
        assertEq(morpho.borrowShares(id, BORROWER), sharesBorrowed, "borrow shares");
        assertEq(morpho.borrowShares(id, BORROWER), sharesBorrowed, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), expectedAmountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountSupplied - expectedAmountBorrowed, "morpho balance");
    }

    function testBorrowAssetsOnBehalf(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(morpho));
        vm.assume(receiver != address(0) && receiver != address(morpho));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(onBehalf, amountCollateral);

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 expectedBorrowShares = amountBorrowed * SharesMathLib.VIRTUAL_SHARES;

        vm.prank(BORROWER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, onBehalf, receiver, amountBorrowed, expectedBorrowShares);
        morpho.borrow(market, amountBorrowed, 0, onBehalf, receiver);

        assertEq(morpho.borrowShares(id, onBehalf), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountSupplied - amountBorrowed, "morpho balance");
    }

    function testBorrowSharesOnBehalf(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 sharesBorrowed,
        uint256 priceCollateral,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(morpho));
        vm.assume(receiver != address(0) && receiver != address(morpho));

        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        sharesBorrowed = bound(sharesBorrowed, MIN_TEST_SHARES, MAX_TEST_SHARES);
        uint256 expectedAmountBorrowed = sharesBorrowed.mulDivDown(1, SharesMathLib.VIRTUAL_SHARES);

        uint256 expectedBorrowedValue =
            sharesBorrowed.mulDivUp(expectedAmountBorrowed + 1, sharesBorrowed + SharesMathLib.VIRTUAL_SHARES);
        uint256 minCollateral = expectedBorrowedValue.wDivUp(market.lltv).mulDivUp(ORACLE_PRICE_SCALE, priceCollateral);
        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, MAX_TEST_AMOUNT));

        amountSupplied = bound(amountSupplied, expectedAmountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(onBehalf, amountCollateral);

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        vm.prank(BORROWER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Borrow(id, BORROWER, onBehalf, receiver, expectedAmountBorrowed, sharesBorrowed);
        morpho.borrow(market, 0, sharesBorrowed, onBehalf, receiver);

        assertEq(morpho.borrowShares(id, onBehalf), sharesBorrowed, "borrow shares");
        assertEq(morpho.totalBorrow(id), expectedAmountBorrowed, "total borrow");
        assertEq(morpho.totalBorrowShares(id), sharesBorrowed, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), expectedAmountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountSupplied - expectedAmountBorrowed, "morpho balance");
    }
}
