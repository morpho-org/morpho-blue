// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationRepayTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testRepayMarketNotCreated(Config memory configFuzz) public {
        vm.assume(neq(configFuzz, market));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.repay(configFuzz, 1, 0, address(this), hex"");
    }

    function testRepayZeroAmount() public {
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.repay(market, 0, 0, address(this), hex"");
    }

    function testRepayInconsistentInput(uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.repay(market, amount, shares, address(this), hex"");
    }

    function testRepayOnBehalfZeroAddress(uint256 input, bool isAmount) public {
        input = bound(input, 1, type(uint256).max);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.repay(market, isAmount ? input : 0, isAmount ? 0 : input, address(0), hex"");
    }

    function testRepayAssets(
        uint256 amountSupplied,
        uint256 amountCollateral,
        uint256 amountBorrowed,
        uint256 amountRepaid,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        amountRepaid = bound(amountRepaid, 1, amountBorrowed);
        uint256 expectedBorrowShares = amountBorrowed.toSharesUp(0, 0);
        uint256 expectedRepaidShares = amountRepaid.toSharesDown(amountBorrowed, expectedBorrowShares);

        collateralToken.setBalance(ONBEHALF, amountCollateral);
        borrowableToken.setBalance(REPAYER, amountRepaid);

        vm.startPrank(ONBEHALF);
        morpho.supplyCollateral(market, amountCollateral, ONBEHALF, hex"");
        morpho.borrow(market, amountBorrowed, 0, ONBEHALF, RECEIVER);
        vm.stopPrank();

        vm.prank(REPAYER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Repay(id, REPAYER, ONBEHALF, amountRepaid, expectedRepaidShares);
        (uint256 returnAssets, uint256 returnShares) = morpho.repay(market, amountRepaid, 0, ONBEHALF, hex"");

        expectedBorrowShares -= expectedRepaidShares;

        assertEq(returnAssets, amountRepaid, "returned asset amount");
        assertEq(returnShares, expectedRepaidShares, "returned shares amount");
        assertEq(morpho.borrowShares(id, ONBEHALF), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrow(id), amountBorrowed - amountRepaid, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), amountBorrowed, "RECEIVER balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)), amountSupplied - amountBorrowed + amountRepaid, "morpho balance"
        );
    }

    function testRepayShares(
        uint256 amountSupplied,
        uint256 amountCollateral,
        uint256 amountBorrowed,
        uint256 sharesRepaid,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        uint256 expectedBorrowShares = amountBorrowed.toSharesUp(0, 0);
        sharesRepaid = bound(sharesRepaid, 1, expectedBorrowShares);
        uint256 expectedAmountRepaid = sharesRepaid.toAssetsUp(amountBorrowed, expectedBorrowShares);

        collateralToken.setBalance(ONBEHALF, amountCollateral);
        borrowableToken.setBalance(REPAYER, expectedAmountRepaid);

        vm.startPrank(ONBEHALF);
        morpho.supplyCollateral(market, amountCollateral, ONBEHALF, hex"");
        morpho.borrow(market, amountBorrowed, 0, ONBEHALF, RECEIVER);
        vm.stopPrank();

        vm.prank(REPAYER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Repay(id, REPAYER, ONBEHALF, expectedAmountRepaid, sharesRepaid);
        (uint256 returnAssets, uint256 returnShares) = morpho.repay(market, 0, sharesRepaid, ONBEHALF, hex"");

        expectedBorrowShares -= sharesRepaid;

        assertEq(returnAssets, expectedAmountRepaid, "returned asset amount");
        assertEq(returnShares, sharesRepaid, "returned shares amount");
        assertEq(morpho.borrowShares(id, ONBEHALF), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrow(id), amountBorrowed - expectedAmountRepaid, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), amountBorrowed, "RECEIVER balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed + expectedAmountRepaid,
            "morpho balance"
        );
    }
}
