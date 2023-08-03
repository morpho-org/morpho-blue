// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationBorrowTest is BlueBaseTest {
    using FixedPointMathLib for uint256;

    function testBorrowUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.borrow(marketFuzz, 1, address(this), address(this));
    }

    function testBorrowZeroAmount() public {
        vm.prank(BORROWER);

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.borrow(market, 0, address(this), address(this));
    }

    function testBorrowToZeroAddress() public {
        vm.prank(BORROWER);

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.borrow(market, 1, BORROWER, address(0));
    }

    function testBorrowUnauthorized(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.prank(BORROWER);
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.borrow(market, amount, address(this), BORROWER);
    }

    function testBorrowUnhealthyPosition(
        uint256 amountCollateral,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        vm.assume(
            amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv)
                < amountBorrowed.mulWadUp(priceBorrowable)
        );

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountBorrowed, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testBorrowUnsufficientLiquidity(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        vm.assume(
            amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv)
                >= amountBorrowed.mulWadUp(priceBorrowable)
        );
        vm.assume(amountSupplied < amountBorrowed);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testBorrow(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        vm.assume(
            amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv)
                >= amountBorrowed.mulWadUp(priceBorrowable)
        );
        vm.assume(amountSupplied >= amountBorrowed);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        assertEq(blue.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(blue.borrowShares(id, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow shares");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed, "blue balance");
    }

    function testBorrowOnBehalf(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        vm.assume(
            amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv)
                >= amountBorrowed.mulWadUp(priceBorrowable)
        );
        vm.assume(amountSupplied >= amountBorrowed);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(address(this), amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");
        blue.supplyCollateral(market, amountCollateral, address(this), hex"");
        blue.setAuthorization(BORROWER, true);

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, address(this), address(this));

        assertEq(blue.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(blue.borrowShares(id, address(this)), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow shares");
        assertEq(borrowableAsset.balanceOf(BORROWER), 0, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(this)), amountBorrowed, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed, "blue balance");
    }
}
