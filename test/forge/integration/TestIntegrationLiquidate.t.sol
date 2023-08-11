// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationLiquidateTest is BaseTest {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;

    function testLiquidateNotCreatedMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.liquidate(marketFuzz, address(this), 1, hex"");
    }

    function testLiquidateZeroAmount() public {
        vm.prank(BORROWER);

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        morpho.liquidate(market, address(this), 0, hex"");
    }

    function testLiquidateHealthyPosition(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountSeized,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        amountSeized = bound(amountSeized, 1, amountCollateral);

        oracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.prank(LIQUIDATOR);
        vm.expectRevert(bytes(ErrorsLib.HEALTHY_POSITION));
        morpho.liquidate(market, BORROWER, amountSeized, hex"");
    }

    function testLiquidateNoBadDebt(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountSeized,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundUnhealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        vm.assume(amountCollateral > 1);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        uint256 incentive = _liquidationIncentive(market.lltv);
        uint256 maxSeized = amountBorrowed.wMulDown(incentive).wDivDown(priceCollateral);
        amountSeized = bound(amountSeized, 1, min(maxSeized, amountCollateral - 1));
        uint256 expectedRepaid = amountSeized.wMulUp(priceCollateral).wDivUp(incentive);

        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        oracle.setPrice((amountCollateral * WAD).wMulUp(LLTV) * amountBorrowed);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(priceCollateral);

        uint256 expectedRepaidShares = expectedRepaid.toSharesDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id));

        vm.prank(LIQUIDATOR);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Liquidate(id, LIQUIDATOR, BORROWER, expectedRepaid, expectedRepaidShares, amountSeized, 0);
        morpho.liquidate(market, BORROWER, amountSeized, hex"");

        uint256 expectedBorrowShares = amountBorrowed * SharesMathLib.VIRTUAL_SHARES - expectedRepaidShares;

        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrow(id), amountBorrowed - expectedRepaid, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(morpho.collateral(id, BORROWER), amountCollateral - amountSeized, "collateral");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(LIQUIDATOR), amountBorrowed - expectedRepaid, "liquidator balance");
        assertEq(
            borrowableAsset.balanceOf(address(morpho)), amountSupplied - amountBorrowed + expectedRepaid, "morpho balance"
        );
        assertEq(collateralAsset.balanceOf(address(morpho)), amountCollateral - amountSeized, "morpho collateral balance");
        assertEq(collateralAsset.balanceOf(LIQUIDATOR), amountSeized, "liquidator collateral balance");
    }

    struct LiquidateBadDebtTestParams {
        uint256 incentive;
        uint256 expectedRepaid;
        uint256 expectedRepaidShares;
        uint256 borrowSharesBeforeLiquidation;
        uint256 totalBorrowSharesBeforeLiquidation;
        uint256 totalBorrowBeforeLiquidation;
        uint256 totalSupplyBeforeLiquidation;
        uint256 expectedBadDebt;
    }

    function testLiquidateBadDebt(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        LiquidateBadDebtTestParams memory params;

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundUnhealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        vm.assume(amountCollateral > 1);

        params.incentive = _liquidationIncentive(market.lltv);
        params.expectedRepaid = amountCollateral.wMulUp(priceCollateral).wDivUp(params.incentive);

        uint256 minBorrowed = max(params.expectedRepaid, amountBorrowed);
        amountBorrowed = bound(amountBorrowed, minBorrowed, max(minBorrowed, MAX_TEST_AMOUNT));

        amountSupplied = bound(amountSupplied, amountBorrowed, max(amountBorrowed, MAX_TEST_AMOUNT));
        _provideLiquidity(amountSupplied);

        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        oracle.setPrice((amountCollateral * WAD).wMulUp(LLTV) * amountBorrowed);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(priceCollateral);

        params.expectedRepaidShares =
            params.expectedRepaid.toSharesDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        params.borrowSharesBeforeLiquidation = morpho.borrowShares(id, BORROWER);
        params.totalBorrowSharesBeforeLiquidation = morpho.totalBorrowShares(id);
        params.totalBorrowBeforeLiquidation = morpho.totalBorrow(id);
        params.totalSupplyBeforeLiquidation = morpho.totalSupply(id);
        params.expectedBadDebt = (params.borrowSharesBeforeLiquidation - params.expectedRepaidShares).toAssetsUp(
            params.totalBorrowBeforeLiquidation - params.expectedRepaid,
            params.totalBorrowSharesBeforeLiquidation - params.expectedRepaidShares
        );

        vm.prank(LIQUIDATOR);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Liquidate(
            id,
            LIQUIDATOR,
            BORROWER,
            params.expectedRepaid,
            params.expectedRepaidShares,
            amountCollateral,
            params.expectedBadDebt * SharesMathLib.VIRTUAL_SHARES
        );
        morpho.liquidate(market, BORROWER, amountCollateral, hex"");

        assertEq(morpho.collateral(id, BORROWER), 0, "collateral");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(LIQUIDATOR), amountBorrowed - params.expectedRepaid, "liquidator balance");
        assertEq(
            borrowableAsset.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed + params.expectedRepaid,
            "morpho balance"
        );
        assertEq(collateralAsset.balanceOf(address(morpho)), 0, "morpho collateral balance");
        assertEq(collateralAsset.balanceOf(LIQUIDATOR), amountCollateral, "liquidator collateral balance");

        // Bad debt realization.
        assertEq(morpho.borrowShares(id, BORROWER), 0, "borrow shares");
        assertEq(morpho.totalBorrowShares(id), 0, "total borrow shares");
        assertEq(
            morpho.totalBorrow(id),
            params.totalBorrowBeforeLiquidation - params.expectedRepaid - params.expectedBadDebt,
            "total borrow"
        );
        assertEq(morpho.totalSupply(id), params.totalSupplyBeforeLiquidation - params.expectedBadDebt, "total supply");
    }
}
