// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationRepayTest is BaseTest {
    function testRepayMarketNotCreated(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.repay(marketFuzz, 1, address(this), hex"");
    }

    function testRepayZeroAmount() public {
        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.repay(market, 0, address(this), hex"");
    }

    function testRepayOnBehalfZeroAddress() public {
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.repay(market, 1, address(0), hex"");
    }

    function testRepay(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid) public {
        amountLent = bound(amountLent, 1, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Repay(id, BORROWER, BORROWER, amountRepaid, amountRepaid * SharesMath.VIRTUAL_SHARES);
        blue.repay(market, amountRepaid, BORROWER, hex"");

        vm.stopPrank();

        uint256 expectedBorrowShares = (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES;

        assertEq(blue.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(blue.totalBorrow(id), amountBorrowed - amountRepaid, "total borrow");
        assertEq(blue.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed - amountRepaid, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testRepayOnBehalf(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid, address onBehalf)
        public
    {
        amountLent = bound(amountLent, 1, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        borrowableAsset.setBalance(onBehalf, amountRepaid);
        blue.supply(market, amountLent, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        vm.startPrank(onBehalf);
        borrowableAsset.approve(address(blue), amountRepaid);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Repay(id, onBehalf, BORROWER, amountRepaid, amountRepaid * SharesMath.VIRTUAL_SHARES);
        blue.repay(market, amountRepaid, BORROWER, hex"");

        vm.stopPrank();

        uint256 expectedBorrowShares = (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES;

        assertEq(blue.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(blue.totalBorrow(id), amountBorrowed - amountRepaid, "total borrow");
        assertEq(blue.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }
}
