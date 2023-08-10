// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationAccrueInterestsTest is BaseTest {
    using FixedPointMathLib for uint256;

    function testAccrueInterestsNoTimeElapsed(uint256 amountSupplied, uint256 amountBorrowed) public {
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);

        // Set fee parameters.
        vm.prank(OWNER);
        blue.setFeeRecipient(OWNER);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, 0, address(this), hex"");

        collateralAsset.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV));

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), BORROWER, hex"");
        blue.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 totalBorrowBeforeAccrued = blue.totalBorrow(id);
        uint256 totalSupplyBeforeAccrued = blue.totalSupply(id);
        uint256 totalSupplySharesBeforeAccrued = blue.totalSupplyShares(id);

        // Supply then withdraw collateral to trigger accrueInterests function.
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");
        blue.withdrawCollateral(market, 1, address(this), address(this));

        assertEq(blue.totalBorrow(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(blue.totalSupply(id), totalSupplyBeforeAccrued, "total supply");
        assertEq(blue.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(blue.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
    }

    function testAccrueInterestsNoBorrow(uint256 amountSupplied, uint256 timeElapsed) public {
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));

        // Set fee parameters.
        vm.prank(OWNER);
        blue.setFeeRecipient(OWNER);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, 0, address(this), hex"");

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 totalBorrowBeforeAccrued = blue.totalBorrow(id);
        uint256 totalSupplyBeforeAccrued = blue.totalSupply(id);
        uint256 totalSupplySharesBeforeAccrued = blue.totalSupplyShares(id);

        // Supply then withdraw collateral to trigger `_accrueInterests` function.
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");
        blue.withdrawCollateral(market, 1, address(this), address(this));

        assertEq(blue.totalBorrow(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(blue.totalSupply(id), totalSupplyBeforeAccrued, "total supply");
        assertEq(blue.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(blue.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
        assertEq(blue.lastUpdate(id), block.timestamp, "last update");
    }

    function testAccrueInterestNoFee(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed) public {
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));

        // Set fee parameters.
        vm.prank(OWNER);
        blue.setFeeRecipient(OWNER);

        borrowableAsset.setBalance(address(this), amountSupplied);
        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, 0, address(this), hex"");

        collateralAsset.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV));

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), BORROWER, hex"");
        blue.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 borrowRate = (blue.totalBorrow(id).wDivDown(blue.totalSupply(id))) / 365 days;
        uint256 totalBorrowBeforeAccrued = blue.totalBorrow(id);
        uint256 totalSupplyBeforeAccrued = blue.totalSupply(id);
        uint256 totalSupplySharesBeforeAccrued = blue.totalSupplyShares(id);
        uint256 expectedAccruedInterests =
            totalBorrowBeforeAccrued.wMulDown(borrowRate.wTaylorCompounded(timeElapsed));

        // Supply then withdraw collateral to trigger `_accrueInterests` function.
        collateralAsset.setBalance(address(this), 1);

        blue.supplyCollateral(market, 1, address(this), hex"");

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.AccrueInterests(id, borrowRate, expectedAccruedInterests, 0);
        blue.withdrawCollateral(market, 1, address(this), address(this));

        assertEq(blue.totalBorrow(id), totalBorrowBeforeAccrued + expectedAccruedInterests, "total borrow");
        assertEq(blue.totalSupply(id), totalSupplyBeforeAccrued + expectedAccruedInterests, "total supply");
        assertEq(blue.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(blue.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
        assertEq(blue.lastUpdate(id), block.timestamp, "last update");
    }

    struct AccrueInterestWithFeesTestParams {
        uint256 borrowRate;
        uint256 totalBorrowBeforeAccrued;
        uint256 totalSupplyBeforeAccrued;
        uint256 totalSupplySharesBeforeAccrued;
        uint256 expectedAccruedInterests;
        uint256 feeAmount;
        uint256 feeShares;
    }

    function testAccrueInterestWithFees(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee
    ) public {
        AccrueInterestWithFeesTestParams memory params;

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));
        fee = bound(fee, 1, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        blue.setFeeRecipient(OWNER);
        blue.setFee(market, fee);
        vm.stopPrank();

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, 0, address(this), hex"");

        collateralAsset.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV));

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), BORROWER, hex"");
        blue.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        params.borrowRate = (blue.totalBorrow(id).wDivDown(blue.totalSupply(id))) / 365 days;
        params.totalBorrowBeforeAccrued = blue.totalBorrow(id);
        params.totalSupplyBeforeAccrued = blue.totalSupply(id);
        params.totalSupplySharesBeforeAccrued = blue.totalSupplyShares(id);
        params.expectedAccruedInterests =
            params.totalBorrowBeforeAccrued.wMulDown(params.borrowRate.wTaylorCompounded(timeElapsed));
        params.feeAmount = params.expectedAccruedInterests.wMulDown(fee);
        params.feeShares = params.feeAmount.mulDivDown(
            params.totalSupplySharesBeforeAccrued,
            params.totalSupplyBeforeAccrued + params.expectedAccruedInterests - params.feeAmount
        );

        // Supply then withdraw collateral to trigger `_accrueInterests` function.
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.AccrueInterests(id, params.borrowRate, params.expectedAccruedInterests, params.feeShares);
        blue.withdrawCollateral(market, 1, address(this), address(this));

        assertEq(
            blue.totalBorrow(id), params.totalBorrowBeforeAccrued + params.expectedAccruedInterests, "total borrow"
        );
        assertEq(
            blue.totalSupply(id), params.totalSupplyBeforeAccrued + params.expectedAccruedInterests, "total supply"
        );
        assertEq(
            blue.totalSupplyShares(id), params.totalSupplySharesBeforeAccrued + params.feeShares, "total supply shares"
        );
        assertEq(blue.supplyShares(id, OWNER), params.feeShares, "feeRecipient's supply shares");
        assertEq(blue.lastUpdate(id), block.timestamp, "last update");
    }
}
