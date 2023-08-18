// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationAccrueInterestTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testAccrueInterestMarketNotCreated(Info memory marketFuzz) public {
        vm.assume(neq(market, marketFuzz));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.accrueInterest(marketFuzz);
    }

    function testAccrueInterestNoTimeElapsed(uint256 amountSupplied, uint256 amountBorrowed) public {
        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) = _boundHealthyPosition(amountCollateral, amountBorrowed, collateralPrice);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 totalBorrowBeforeAccrued = morpho.totalBorrow(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupply(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);

        morpho.accrueInterest(market);

        assertEq(morpho.totalBorrow(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(morpho.totalSupply(id), totalSupplyBeforeAccrued, "total supply");
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
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 totalBorrowBeforeAccrued = morpho.totalBorrow(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupply(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);

        morpho.accrueInterest(market);

        assertEq(morpho.totalBorrow(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(morpho.totalSupply(id), totalSupplyBeforeAccrued, "total supply");
        assertEq(morpho.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(morpho.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
        assertEq(morpho.lastUpdate(id), block.timestamp, "last update");
    }

    function testAccrueInterestNoFee(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed) public {
        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) = _boundHealthyPosition(amountCollateral, amountBorrowed, collateralPrice);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 borrowRate = (morpho.totalBorrow(id).wDivDown(morpho.totalSupply(id))) / 365 days;
        uint256 totalBorrowBeforeAccrued = morpho.totalBorrow(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupply(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);
        uint256 expectedAccruedInterest = totalBorrowBeforeAccrued.wMulDown(borrowRate.wTaylorCompounded(timeElapsed));

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.AccrueInterest(id, borrowRate, expectedAccruedInterest, 0);
        morpho.accrueInterest(market);

        assertEq(morpho.totalBorrow(id), totalBorrowBeforeAccrued + expectedAccruedInterest, "total borrow");
        assertEq(morpho.totalSupply(id), totalSupplyBeforeAccrued + expectedAccruedInterest, "total supply");
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
        uint128 fee
    ) public {
        AccrueInterestWithFeesTestParams memory params;

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) = _boundHealthyPosition(amountCollateral, amountBorrowed, collateralPrice);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        timeElapsed = uint32(bound(timeElapsed, 1, 1e8));
        fee = uint128(bound(fee, 1, MAX_FEE));

        // Set fee parameters.
        vm.startPrank(OWNER);
        morpho.setFeeRecipient(OWNER);
        morpho.setFee(market, fee);
        vm.stopPrank();

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        params.borrowRate = (morpho.totalBorrow(id).wDivDown(morpho.totalSupply(id))) / 365 days;
        params.totalBorrowBeforeAccrued = morpho.totalBorrow(id);
        params.totalSupplyBeforeAccrued = morpho.totalSupply(id);
        params.totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);
        params.expectedAccruedInterest =
            params.totalBorrowBeforeAccrued.wMulDown(params.borrowRate.wTaylorCompounded(timeElapsed));
        params.feeAmount = params.expectedAccruedInterest.wMulDown(fee);
        params.feeShares = params.feeAmount.toSharesDown(
            params.totalSupplyBeforeAccrued + params.expectedAccruedInterest - params.feeAmount,
            params.totalSupplySharesBeforeAccrued
        );

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.AccrueInterest(id, params.borrowRate, params.expectedAccruedInterest, params.feeShares);
        morpho.accrueInterest(market);

        assertEq(
            morpho.totalSupply(id), params.totalSupplyBeforeAccrued + params.expectedAccruedInterest, "total supply"
        );
        assertEq(
            morpho.totalBorrow(id), params.totalBorrowBeforeAccrued + params.expectedAccruedInterest, "total borrow"
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
