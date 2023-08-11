// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationRepayTest is BaseTest {
    using FixedPointMathLib for uint256;

    function testRepayMarketNotCreated(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.repay(marketFuzz, 1, 0, address(this), hex"");
    }

    function testRepayZeroAmount() public {
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.repay(market, 0, 0, address(this), hex"");
    }

    function testRepayInconsistentInput(uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.repay(market, amount, shares, address(this), hex"");
    }

    function testRepayOnBehalfZeroAddress(uint256 input, bool isAmount) public {
        input = bound(input, 1, type(uint256).max);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.repay(market, isAmount ? input : 0, isAmount ? 0 : input, address(0), hex"");
    }

    function testRepayAmount(
        uint256 amountSupplied,
        uint256 amountCollateral,
        uint256 amountBorrowed,
        uint256 amountRepaid,
        uint256 priceCollateral,
        address repayer,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(repayer != address(0) && repayer != address(blue));
        vm.assume(onBehalf != address(0) && onBehalf != address(blue));
        vm.assume(receiver != address(0) && receiver != address(blue));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        collateralAsset.setBalance(onBehalf, amountCollateral);
        borrowableAsset.setBalance(repayer, amountRepaid);

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(blue), amountCollateral);
        blue.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        blue.borrow(market, amountBorrowed, 0, onBehalf, receiver);
        vm.stopPrank();

        vm.startPrank(repayer);
        borrowableAsset.approve(address(blue), amountRepaid);

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.Repay(id, repayer, onBehalf, amountRepaid, amountRepaid * SharesMathLib.VIRTUAL_SHARES);
        blue.repay(market, amountRepaid, 0, onBehalf, hex"");

        vm.stopPrank();

        uint256 expectedBorrowShares = (amountBorrowed - amountRepaid) * SharesMathLib.VIRTUAL_SHARES;

        assertEq(blue.borrowShares(id, onBehalf), expectedBorrowShares, "borrow shares");
        assertEq(blue.totalBorrow(id), amountBorrowed - amountRepaid, "total borrow");
        assertEq(blue.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed + amountRepaid, "blue balance"
        );
    }

    function testRepayShares(
        uint256 amountSupplied,
        uint256 amountCollateral,
        uint256 amountBorrowed,
        uint256 sharesRepaid,
        uint256 priceCollateral,
        address repayer,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(repayer != address(0) && repayer != address(blue));
        vm.assume(onBehalf != address(0) && onBehalf != address(blue));
        vm.assume(receiver != address(0) && receiver != address(blue));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        uint256 expectedBorrowShares = amountBorrowed * SharesMathLib.VIRTUAL_SHARES;
        vm.assume(expectedBorrowShares != 0);

        sharesRepaid = bound(sharesRepaid, 1, expectedBorrowShares);
        uint256 expectedAmountRepaid =
            sharesRepaid.mulDivUp(amountBorrowed + 1, expectedBorrowShares + SharesMathLib.VIRTUAL_SHARES);

        collateralAsset.setBalance(onBehalf, amountCollateral);
        borrowableAsset.setBalance(repayer, expectedAmountRepaid);

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(blue), amountCollateral);
        blue.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        blue.borrow(market, amountBorrowed, 0, onBehalf, receiver);
        vm.stopPrank();

        vm.startPrank(repayer);
        borrowableAsset.approve(address(blue), expectedAmountRepaid);

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.Repay(id, repayer, onBehalf, expectedAmountRepaid, sharesRepaid);
        blue.repay(market, 0, sharesRepaid, onBehalf, hex"");

        vm.stopPrank();

        expectedBorrowShares -= sharesRepaid;

        assertEq(blue.borrowShares(id, onBehalf), expectedBorrowShares, "borrow shares");
        assertEq(blue.totalBorrow(id), amountBorrowed - expectedAmountRepaid, "total borrow");
        assertEq(blue.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)),
            amountSupplied - amountBorrowed + expectedAmountRepaid,
            "blue balance"
        );
    }
}
