// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract AccrueInterestIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testAccrueInterestNoTimeElapsed(uint256 amountSupplied, uint256 amountBorrowed) public {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) = _boundHealthyPosition(amountCollateral, amountBorrowed, collateralPrice);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);

        _accrueInterest(marketParams);

        assertEq(morpho.totalBorrowAssets(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(morpho.totalSupplyAssets(id), totalSupplyBeforeAccrued, "total supply");
        assertEq(morpho.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(morpho.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
    }

    function testAccrueInterestNoBorrow(uint256 amountSupplied, uint256 timeElapsed) public {
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);

        _accrueInterest(marketParams);

        assertEq(morpho.totalBorrowAssets(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(morpho.totalSupplyAssets(id), totalSupplyBeforeAccrued, "total supply");
        assertEq(morpho.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(morpho.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
        assertEq(morpho.lastUpdate(id), block.timestamp, "last update");
    }

    function testAccrueInterestNoFee(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed) public {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) = _boundHealthyPosition(amountCollateral, amountBorrowed, collateralPrice);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");

        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 borrowRate = (morpho.totalBorrowAssets(id).wDivDown(morpho.totalSupplyAssets(id))) / 365 days;
        uint256 totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);
        uint256 expectedAccruedInterest = totalBorrowBeforeAccrued.wMulDown(borrowRate.wTaylorCompounded(timeElapsed));

        collateralToken.setBalance(address(this), 1);
        morpho.supplyCollateral(marketParams, 1, address(this), hex"");
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.AccrueInterest(id, borrowRate, expectedAccruedInterest, 0);
        // Accrues interest.
        morpho.withdrawCollateral(marketParams, 1, address(this), address(this));

        assertEq(morpho.totalBorrowAssets(id), totalBorrowBeforeAccrued + expectedAccruedInterest, "total borrow");
        assertEq(morpho.totalSupplyAssets(id), totalSupplyBeforeAccrued + expectedAccruedInterest, "total supply");
        assertEq(morpho.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(morpho.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
        assertEq(morpho.lastUpdate(id), block.timestamp, "last update");
    }

    struct AccrueInterestWithFeesTestParams {
        uint256 borrowRate;
        uint256 totalBorrowBeforeAccrued;
        uint256 totalSupplyBeforeAccrued;
        uint256 totalSupplySharesBeforeAccrued;
        uint256 expectedAccruedInterest;
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

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) = _boundHealthyPosition(amountCollateral, amountBorrowed, collateralPrice);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        timeElapsed = uint32(bound(timeElapsed, 1, 1e8));
        fee = bound(fee, 1, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        morpho.setFeeRecipient(OWNER);
        if (fee != morpho.fee(id)) morpho.setFee(marketParams, fee);
        vm.stopPrank();

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        params.borrowRate = (morpho.totalBorrowAssets(id).wDivDown(morpho.totalSupplyAssets(id))) / 365 days;
        params.totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        params.totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        params.totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);
        params.expectedAccruedInterest =
            params.totalBorrowBeforeAccrued.wMulDown(params.borrowRate.wTaylorCompounded(timeElapsed));
        params.feeAmount = params.expectedAccruedInterest.wMulDown(fee);
        params.feeShares = params.feeAmount.toSharesDown(
            params.totalSupplyBeforeAccrued + params.expectedAccruedInterest - params.feeAmount,
            params.totalSupplySharesBeforeAccrued
        );

        collateralToken.setBalance(address(this), 1);
        morpho.supplyCollateral(marketParams, 1, address(this), hex"");
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.AccrueInterest(id, params.borrowRate, params.expectedAccruedInterest, params.feeShares);
        // Accrues interest.
        morpho.withdrawCollateral(marketParams, 1, address(this), address(this));

        assertEq(
            morpho.totalSupplyAssets(id),
            params.totalSupplyBeforeAccrued + params.expectedAccruedInterest,
            "total supply"
        );
        assertEq(
            morpho.totalBorrowAssets(id),
            params.totalBorrowBeforeAccrued + params.expectedAccruedInterest,
            "total borrow"
        );
        assertEq(
            morpho.totalSupplyShares(id),
            params.totalSupplySharesBeforeAccrued + params.feeShares,
            "total supply shares"
        );
        assertEq(morpho.supplyShares(id, OWNER), params.feeShares, "feeRecipient's supply shares");
        assertEq(morpho.lastUpdate(id), block.timestamp, "last update");
    }
}
