// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationLiquidateTest is BlueBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    function testLiquidateUnknownMarket(Market memory marketFuzz) public {
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
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        amountSeized = bound(amountSeized, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 1, 2 ** 64);

        uint256 incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);
        uint256 expectedRepaid = amountSeized.mulWadUp(priceCollateral).divWadUp(incentive).divWadUp(priceBorrowable);

        vm.assume(
            amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv) + 2
                < amountBorrowed.mulWadUp(priceBorrowable)
        );
        vm.assume(amountSupplied >= amountBorrowed);
        vm.assume(expectedRepaid < amountBorrowed && amountSeized < amountCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        uint256 expectedRepaidShares = expectedRepaid.toSharesDown(blue.totalBorrow(id), blue.totalBorrowShares(id));

        vm.prank(LIQUIDATOR);
        blue.liquidate(market, BORROWER, amountSeized, hex"");

        assertEq(
            blue.borrowShares(id, BORROWER),
            amountBorrowed * SharesMath.VIRTUAL_SHARES - expectedRepaidShares,
            "borrow share"
        );
        assertEq(blue.totalBorrow(id), amountBorrowed - expectedRepaid, "borrow shares");
        assertEq(blue.collateral(id, BORROWER), amountCollateral - amountSeized, "collateral");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(LIQUIDATOR), amountBorrowed - expectedRepaid, "liquidator balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed + expectedRepaid, "blue balance"
        );
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral - amountSeized, "blue collateral balance");
        assertEq(collateralAsset.balanceOf(LIQUIDATOR), amountSeized, "blue collateral balance");
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
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        LiquidateBadDebtTestParams memory params;

        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 1, 2 ** 64);

        params.incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);
        params.expectedRepaid =
            amountCollateral.mulWadUp(priceCollateral).divWadUp(params.incentive).divWadUp(priceBorrowable);

        vm.assume(
            amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv) + 2
                < amountBorrowed.mulWadUp(priceBorrowable)
        );
        vm.assume(amountSupplied >= amountBorrowed);
        vm.assume(params.expectedRepaid < amountBorrowed);

        borrowableAsset.setBalance(address(this), amountSupplied);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        borrowableOracle.setPrice(priceBorrowable);
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
        assertEq(collateralAsset.balanceOf(LIQUIDATOR), amountCollateral, "blue collateral balance");

        //bad debt realisation
        assertEq(blue.borrowShares(id, BORROWER), 0, "borrow sharse");
        assertEq(blue.totalBorrowShares(id), 0, "total borrow shares");
        assertEq(
            blue.totalBorrow(id),
            params.totalBorrowBeforeLiquidation - params.expectedRepaid - params.expectedBadDebt,
            "total borrow"
        );
        assertEq(blue.totalSupply(id), params.totalSupplyBeforeLiquidation - params.expectedBadDebt, "total borrow");
    }
}
