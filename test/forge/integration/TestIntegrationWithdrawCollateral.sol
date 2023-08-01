// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationWithdrawCollateralTest is BlueBaseTest {
    using FixedPointMathLib for uint256;

    function testWithdrawCollateralUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert("market not created");
        blue.withdrawCollateral(marketFuzz, 1, address(this), address(this));
    }

    function testWithdrawCollateralZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, address(this), hex"");

        vm.expectRevert("zero amount");
        blue.withdrawCollateral(market, 0, address(this), address(this));
    }

    function testWithdrawCollateralUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, address(this), hex"");
        
        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blue.withdrawCollateral(market, amount, address(this), address(this));
    }

    function testWithdrawCollateralUnhealthyPosition(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);

        vm.assume(amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv) >= amountBorrowed.mulWadUp(priceBorrowable));
        vm.assume(amountSupplied >= amountBorrowed);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.expectRevert("insufficient collateral");
        blue.withdrawCollateral(market, amountCollateral, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testWithdrawCollateral(
        uint256 amountCollateral,
        uint256 amountCollateralExcess,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        amountCollateralExcess = bound(amountCollateralExcess, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);

        vm.assume(amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv) >= amountBorrowed.mulWadUp(priceBorrowable));
        vm.assume(amountSupplied >= amountBorrowed);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountCollateral + amountCollateralExcess);

        blue.supply(market, amountSupplied, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral + amountCollateralExcess, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        blue.withdrawCollateral(market, amountCollateralExcess, BORROWER, BORROWER);
        vm.stopPrank();

        assertEq(blue.collateral(id, BORROWER), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(BORROWER), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral, "blue balance");
    }

    function testWithdrawCollateralOnBehalf(
        uint256 amountCollateral,
        uint256 amountCollateralExcess,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        amountCollateralExcess = bound(amountCollateralExcess, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);

        vm.assume(amountCollateral.mulWadDown(priceCollateral).mulWadDown(market.lltv) >= amountBorrowed.mulWadUp(priceBorrowable));
        vm.assume(amountSupplied >= amountBorrowed);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(address(this), amountCollateral + amountCollateralExcess);

        blue.supply(market, amountSupplied, address(this), hex"");
        blue.supplyCollateral(market, amountCollateral + amountCollateralExcess, address(this), hex"");
        blue.borrow(market, amountBorrowed, address(this), address(this));
        blue.setAuthorization(BORROWER, true);

        vm.prank(BORROWER);
        blue.withdrawCollateral(market, amountCollateralExcess, address(this), address(this));

        assertEq(blue.collateral(id, address(this)), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(address(this)), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(BORROWER), 0, "lender balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral, "blue balance");
    }
}