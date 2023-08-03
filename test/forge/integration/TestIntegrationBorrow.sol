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
        uint256 priceCollateral
    ) public {
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 10, 2 ** 64);

        uint256 maxCollateral = amountBorrowed.divWadDown(priceCollateral).divWadDown(market.lltv);
        vm.assume(maxCollateral != 0);

        amountCollateral = bound(amountBorrowed, 1, maxCollateral);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
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
        uint256 priceCollateral
    ) public {
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 10, 2 ** 64);
        amountSupplied = bound(amountSupplied, 1, amountBorrowed - 1);

        uint256 minCollateral = amountBorrowed.divWadUp(market.lltv).divWadUp(priceCollateral);
        vm.assume(minCollateral != 0);

        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, 2 ** 64));

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
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
        address receiver
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));

        priceCollateral = bound(priceCollateral, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 10, 2 ** 64);
        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);

        uint256 minCollateral = amountBorrowed.divWadUp(market.lltv).divWadUp(priceCollateral);
        vm.assume(minCollateral != 0);

        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, 2 ** 64));

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        blue.borrow(market, amountBorrowed, BORROWER, receiver);
        vm.stopPrank();

        assertEq(blue.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(blue.borrowShares(id, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed, "blue balance");
    }

    function testBorrowOnBehalf(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0));
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));

        priceCollateral = bound(priceCollateral, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 10, 2 ** 64);
        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);

        _provideLiquidity(amountSupplied);

        uint256 minCollateral = amountBorrowed.divWadUp(market.lltv).divWadUp(priceCollateral);
        vm.assume(minCollateral != 0);

        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, 2 ** 64));

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.setAuthorization(onBehalf, true);
        vm.stopPrank();

        vm.prank(onBehalf);
        blue.borrow(market, amountBorrowed, BORROWER, receiver);

        assertEq(blue.totalBorrow(id), amountBorrowed, "total borrow");
        assertEq(blue.borrowShares(id, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow shares");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed, "blue balance");
    }
}
