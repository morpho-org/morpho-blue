// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationAccrueInterestTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testAccrueInterestMarketNotCreated(Market memory marketFuzz) public {
        vm.assume(neq(market, marketFuzz));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.accrueInterest(marketFuzz);
    }

    function testAccrueInterestNoTimeElapsed(uint256 amountSupplied, uint256 amountBorrowed) public {
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        uint256 collateralPrice = IOracle(market.oracle).price();
        collateralToken.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice));

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(
            market, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice), BORROWER, hex""
        );
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);

        morpho.accrueInterest(market);

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
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);

        morpho.accrueInterest(market);

        assertEq(morpho.totalBorrowAssets(id), totalBorrowBeforeAccrued, "total borrow");
        assertEq(morpho.totalSupplyAssets(id), totalSupplyBeforeAccrued, "total supply");
        assertEq(morpho.totalSupplyShares(id), totalSupplySharesBeforeAccrued, "total supply shares");
        assertEq(morpho.supplyShares(id, OWNER), 0, "feeRecipient's supply shares");
        assertEq(morpho.lastUpdate(id), block.timestamp, "last update");
    }

    function testAccrueInterestNoFee(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed) public {
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        timeElapsed = uint32(bound(timeElapsed, 1, type(uint32).max));

        // Set fee parameters.
        vm.prank(OWNER);
        morpho.setFeeRecipient(OWNER);

        borrowableToken.setBalance(address(this), amountSupplied);
        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        uint256 collateralPrice = IOracle(market.oracle).price();
        collateralToken.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice));

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(
            market, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice), BORROWER, hex""
        );

        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);

        uint256 borrowRate = (morpho.totalBorrowAssets(id).wDivDown(morpho.totalSupplyAssets(id))) / 365 days;
        uint256 totalBorrowBeforeAccrued = morpho.totalBorrowAssets(id);
        uint256 totalSupplyBeforeAccrued = morpho.totalSupplyAssets(id);
        uint256 totalSupplySharesBeforeAccrued = morpho.totalSupplyShares(id);
        uint256 expectedAccruedInterest = totalBorrowBeforeAccrued.wMulDown(borrowRate.wTaylorCompounded(timeElapsed));

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.AccrueInterest(id, borrowRate, expectedAccruedInterest, 0);
        morpho.accrueInterest(market);

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

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        timeElapsed = uint32(bound(timeElapsed, 1, 1e8));
        fee = bound(fee, 1, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        morpho.setFeeRecipient(OWNER);
        morpho.setFee(market, fee);
        vm.stopPrank();

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        uint256 collateralPrice = IOracle(market.oracle).price();
        collateralToken.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice));

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(
            market, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice), BORROWER, hex""
        );
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
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

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.AccrueInterest(id, params.borrowRate, params.expectedAccruedInterest, params.feeShares);
        morpho.accrueInterest(market);

        assertEq(
            morpho.totalBorrowAssets(id),
            params.totalBorrowBeforeAccrued + params.expectedAccruedInterest,
            "total borrow"
        );
        assertEq(
            morpho.totalSupplyAssets(id),
            params.totalSupplyBeforeAccrued + params.expectedAccruedInterest,
            "total supply"
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
