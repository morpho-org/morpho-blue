// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract LiquidateIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testLiquidateNotCreatedMarket(MarketParams memory marketParamsFuzz) public {
        vm.assume(neq(marketParamsFuzz, marketParams));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.liquidate(marketParamsFuzz, address(this), 1, 0, hex"");
    }

    function testLiquidateZeroAmount() public {
        vm.prank(BORROWER);

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.liquidate(marketParams, address(this), 0, 0, hex"");
    }

    function testLiquidateInconsistentInput(uint256 seized, uint256 sharesRepaid) public {
        seized = bound(seized, 1, MAX_TEST_AMOUNT);
        sharesRepaid = bound(sharesRepaid, 1, MAX_TEST_SHARES);

        vm.prank(BORROWER);

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.liquidate(marketParams, address(this), seized, sharesRepaid, hex"");
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
        _supply(amountSupplied);

        amountSeized = bound(amountSeized, 1, amountCollateral);

        oracle.setPrice(priceCollateral);

        borrowableToken.setBalance(LIQUIDATOR, amountBorrowed);
        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.prank(LIQUIDATOR);
        vm.expectRevert(bytes(ErrorsLib.HEALTHY_POSITION));
        morpho.liquidate(marketParams, BORROWER, amountSeized, 0, hex"");
    }

    function testLiquidateSeizedInputNoBadDebt(
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
        _supply(amountSupplied);

        uint256 incentive = _liquidationIncentive(marketParams.lltv);
        uint256 maxSeized = amountBorrowed.wMulDown(incentive).mulDivDown(ORACLE_PRICE_SCALE, priceCollateral);
        amountSeized = bound(amountSeized, 1, min(maxSeized, amountCollateral - 1));
        uint256 expectedRepaid = amountSeized.mulDivUp(priceCollateral, ORACLE_PRICE_SCALE).wDivUp(incentive);

        borrowableToken.setBalance(LIQUIDATOR, amountBorrowed);
        collateralToken.setBalance(BORROWER, amountCollateral);

        oracle.setPrice(type(uint256).max / amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(priceCollateral);

        uint256 expectedRepaidShares =
            expectedRepaid.toSharesDown(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));

        vm.prank(LIQUIDATOR);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Liquidate(id, LIQUIDATOR, BORROWER, expectedRepaid, expectedRepaidShares, amountSeized, 0);
        (uint256 returnSeized, uint256 returnRepaid) = morpho.liquidate(marketParams, BORROWER, amountSeized, 0, hex"");

        uint256 expectedBorrowShares = amountBorrowed.toSharesUp(0, 0) - expectedRepaidShares;

        assertEq(returnSeized, amountSeized, "returned seized amount");
        assertEq(returnRepaid, expectedRepaid, "returned asset amount");
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrowAssets(id), amountBorrowed - expectedRepaid, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(morpho.collateral(id, BORROWER), amountCollateral - amountSeized, "collateral");
        assertEq(borrowableToken.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(LIQUIDATOR), amountBorrowed - expectedRepaid, "liquidator balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed + expectedRepaid,
            "morpho balance"
        );
        assertEq(
            collateralToken.balanceOf(address(morpho)), amountCollateral - amountSeized, "morpho collateral balance"
        );
        assertEq(collateralToken.balanceOf(LIQUIDATOR), amountSeized, "liquidator collateral balance");
    }

    function testLiquidateSharesInputNoBadDebt(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 sharesRepaid,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundUnhealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        vm.assume(amountCollateral > 1);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        uint256 expectedBorrowShares = amountBorrowed.toSharesUp(0, 0);
        uint256 maxRepaidShares = amountCollateral.mulDivDown(priceCollateral, ORACLE_PRICE_SCALE).wDivDown(
            _liquidationIncentive(marketParams.lltv)
        );
        vm.assume(maxRepaidShares != 0);
        sharesRepaid = bound(sharesRepaid, 1, min(maxRepaidShares, expectedBorrowShares));
        uint256 expectedRepaid = sharesRepaid.toAssetsUp(amountBorrowed, expectedBorrowShares);
        uint256 expectedSeized = expectedRepaid.wMulDown(_liquidationIncentive(marketParams.lltv)).mulDivDown(
            ORACLE_PRICE_SCALE, priceCollateral
        );

        borrowableToken.setBalance(LIQUIDATOR, amountBorrowed);
        collateralToken.setBalance(BORROWER, amountCollateral);

        oracle.setPrice(type(uint256).max / amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(priceCollateral);

        vm.prank(LIQUIDATOR);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Liquidate(id, LIQUIDATOR, BORROWER, expectedRepaid, sharesRepaid, expectedSeized, 0);
        (uint256 returnSeized, uint256 returnRepaid) = morpho.liquidate(marketParams, BORROWER, 0, sharesRepaid, hex"");

        expectedBorrowShares = amountBorrowed.toSharesUp(0, 0) - sharesRepaid;

        assertEq(returnSeized, expectedSeized, "returned seized amount");
        assertEq(returnRepaid, expectedRepaid, "returned asset amount");
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
        assertEq(morpho.totalBorrowAssets(id), amountBorrowed - expectedRepaid, "total borrow");
        assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
        assertEq(morpho.collateral(id, BORROWER), amountCollateral - expectedSeized, "collateral");
        assertEq(borrowableToken.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(LIQUIDATOR), amountBorrowed - expectedRepaid, "liquidator balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed + expectedRepaid,
            "morpho balance"
        );
        assertEq(
            collateralToken.balanceOf(address(morpho)), amountCollateral - expectedSeized, "morpho collateral balance"
        );
        assertEq(collateralToken.balanceOf(LIQUIDATOR), expectedSeized, "liquidator collateral balance");
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

        params.incentive = _liquidationIncentive(marketParams.lltv);
        params.expectedRepaid = amountCollateral.mulDivUp(priceCollateral, ORACLE_PRICE_SCALE).wDivUp(params.incentive);

        uint256 minBorrowed = max(params.expectedRepaid, amountBorrowed);
        amountBorrowed = bound(amountBorrowed, minBorrowed, max(minBorrowed, MAX_TEST_AMOUNT));

        amountSupplied = bound(amountSupplied, amountBorrowed, max(amountBorrowed, MAX_TEST_AMOUNT));
        _supply(amountSupplied);

        borrowableToken.setBalance(LIQUIDATOR, amountBorrowed);
        collateralToken.setBalance(BORROWER, amountCollateral);

        oracle.setPrice(type(uint256).max / amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(priceCollateral);

        params.expectedRepaidShares =
            params.expectedRepaid.toSharesDown(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        params.borrowSharesBeforeLiquidation = morpho.borrowShares(id, BORROWER);
        params.totalBorrowSharesBeforeLiquidation = morpho.totalBorrowShares(id);
        params.totalBorrowBeforeLiquidation = morpho.totalBorrowAssets(id);
        params.totalSupplyBeforeLiquidation = morpho.totalSupplyAssets(id);
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
        (uint256 returnSeized, uint256 returnRepaid) =
            morpho.liquidate(marketParams, BORROWER, amountCollateral, 0, hex"");

        assertEq(returnSeized, amountCollateral, "returned seized amount");
        assertEq(returnRepaid, params.expectedRepaid, "returned asset amount");
        assertEq(morpho.collateral(id, BORROWER), 0, "collateral");
        assertEq(borrowableToken.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableToken.balanceOf(LIQUIDATOR), amountBorrowed - params.expectedRepaid, "liquidator balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed + params.expectedRepaid,
            "morpho balance"
        );
        assertEq(collateralToken.balanceOf(address(morpho)), 0, "morpho collateral balance");
        assertEq(collateralToken.balanceOf(LIQUIDATOR), amountCollateral, "liquidator collateral balance");

        // Bad debt realization.
        assertEq(morpho.borrowShares(id, BORROWER), 0, "borrow shares");
        assertEq(morpho.totalBorrowShares(id), 0, "total borrow shares");
        assertEq(
            morpho.totalBorrowAssets(id),
            params.totalBorrowBeforeLiquidation - params.expectedRepaid - params.expectedBadDebt,
            "total borrow"
        );
        assertEq(
            morpho.totalSupplyAssets(id), params.totalSupplyBeforeLiquidation - params.expectedBadDebt, "total supply"
        );
    }
}
