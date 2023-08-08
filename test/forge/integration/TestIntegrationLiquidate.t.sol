// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationLiquidateTest is BlueBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    function testLiquidateNotCreatedMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.liquidate(marketFuzz, address(this), 1, hex"");
    }

    function testLiquidateZeroAmount() public {
        vm.prank(BORROWER);

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.liquidate(market, address(this), 0, hex"");
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

        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);
        _provideLiquidity(amountSupplied);

        amountSeized = bound(amountSeized, 1, amountCollateral);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        vm.prank(LIQUIDATOR);
        vm.expectRevert(bytes(Errors.HEALTHY_POSITION));
        blue.liquidate(market, BORROWER, amountSeized, hex"");
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

        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);
        _provideLiquidity(amountSupplied);

        uint256 incentive = _incentive(market.lltv);
        uint256 maxSeized = amountBorrowed.mulWadDown(incentive).divWadDown(priceCollateral);
        amountSeized = bound(amountSeized, 1, min(maxSeized, amountCollateral - 1));
        uint256 expectedRepaid = amountSeized.mulWadUp(priceCollateral).divWadUp(incentive);

        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        uint256 expectedRepaidShares = expectedRepaid.toSharesDown(blue.totalBorrow(id), blue.totalBorrowShares(id));

        vm.prank(LIQUIDATOR);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Liquidate(id, LIQUIDATOR, BORROWER, expectedRepaid, expectedRepaidShares, amountSeized, 0);
        blue.liquidate(market, BORROWER, amountSeized, hex"");

        assertEq(
            blue.borrowShares(id, BORROWER),
            amountBorrowed * SharesMath.VIRTUAL_SHARES - expectedRepaidShares,
            "borrow share"
        );
        assertEq(blue.totalBorrow(id), amountBorrowed - expectedRepaid, "total borrow");
        assertEq(blue.collateral(id, BORROWER), amountCollateral - amountSeized, "collateral");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(LIQUIDATOR), amountBorrowed - expectedRepaid, "liquidator balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed + expectedRepaid, "blue balance"
        );
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral - amountSeized, "blue collateral balance");
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

        params.incentive = _incentive(market.lltv);
        params.expectedRepaid = amountCollateral.mulWadUp(priceCollateral).divWadUp(params.incentive);

        uint256 minBorrowed = max(params.expectedRepaid, amountBorrowed);
        amountBorrowed = bound(amountBorrowed, minBorrowed, max(minBorrowed, 2 ** 64));

        amountSupplied = bound(amountSupplied, amountBorrowed, max(amountBorrowed, 2 ** 64));
        _provideLiquidity(amountSupplied);

        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        params.expectedRepaidShares =
            params.expectedRepaid.toSharesDown(blue.totalBorrow(id), blue.totalBorrowShares(id));
        params.borrowSharesBeforeLiquidation = blue.borrowShares(id, BORROWER);
        params.totalBorrowSharesBeforeLiquidation = blue.totalBorrowShares(id);
        params.totalBorrowBeforeLiquidation = blue.totalBorrow(id);
        params.totalSupplyBeforeLiquidation = blue.totalSupply(id);
        params.expectedBadDebt = (params.borrowSharesBeforeLiquidation - params.expectedRepaidShares).toAssetsUp(
            params.totalBorrowBeforeLiquidation - params.expectedRepaid,
            params.totalBorrowSharesBeforeLiquidation - params.expectedRepaidShares
        );

        vm.prank(LIQUIDATOR);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Liquidate(
            id,
            LIQUIDATOR,
            BORROWER,
            params.expectedRepaid,
            params.expectedRepaidShares,
            amountCollateral,
            params.expectedBadDebt * SharesMath.VIRTUAL_SHARES
        );
        blue.liquidate(market, BORROWER, amountCollateral, hex"");

        assertEq(blue.collateral(id, BORROWER), 0, "collateral");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(LIQUIDATOR), amountBorrowed - params.expectedRepaid, "liquidator balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)),
            amountSupplied - amountBorrowed + params.expectedRepaid,
            "blue balance"
        );
        assertEq(collateralAsset.balanceOf(address(blue)), 0, "blue collateral balance");
        assertEq(collateralAsset.balanceOf(LIQUIDATOR), amountCollateral, "liquidator collateral balance");

        // Bad debt realization.
        assertEq(blue.borrowShares(id, BORROWER), 0, "borrow shares");
        assertEq(blue.totalBorrowShares(id), 0, "total borrow shares");
        assertEq(
            blue.totalBorrow(id),
            params.totalBorrowBeforeLiquidation - params.expectedRepaid - params.expectedBadDebt,
            "total borrow"
        );
        assertEq(blue.totalSupply(id), params.totalSupplyBeforeLiquidation - params.expectedBadDebt, "total supply");
    }
}
