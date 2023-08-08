// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationWithdrawCollateralTest is BlueBaseTest {
    using FixedPointMathLib for uint256;

    function testWithdrawCollateralMarketNotCreated(Market memory marketFuzz, address supplier, address receiver) public {
        vm.assume(neq(marketFuzz, market) && receiver != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdrawCollateral(marketFuzz, 1, supplier, receiver);
    }

    function testWithdrawCollateralZeroAmount(address supplier, address receiver, uint256 amount) public {
        vm.assume(supplier != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(blue), amount);
        blue.supplyCollateral(market, amount, supplier, hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.withdrawCollateral(market, 0, supplier, receiver);
        vm.stopPrank();
    }

    function testWithdrawCollateralToZeroAddress(address supplier, uint256 amount) public {
        vm.assume(supplier != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(blue), type(uint256).max);
        blue.supplyCollateral(market, amount, supplier, hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdrawCollateral(market, amount, supplier, address(0));
        vm.stopPrank();
    }

    function testWithdrawCollateralUnauthorized(address supplier, address attacker, address receiver, uint256 amount) public {
        vm.assume(supplier != attacker && supplier != address(0) && receiver != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(blue), amount);
        blue.supplyCollateral(market, amount, supplier, hex"");
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdrawCollateral(market, amount, supplier, receiver);
    }

    function testWithdrawCollateralUnhealthyPosition(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
        blue.withdrawCollateral(market, amountCollateral, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function testWithdrawCollateral(
        uint256 amountCollateral,
        uint256 amountCollateralExcess,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(blue));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        amountCollateralExcess = bound(amountCollateralExcess, 1, MAX_TEST_AMOUNT);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral + amountCollateralExcess);

        vm.startPrank(BORROWER);

        blue.supplyCollateral(market, amountCollateral + amountCollateralExcess, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.WithdrawCollateral(id, BORROWER, BORROWER, receiver, amountCollateralExcess);
        blue.withdrawCollateral(market, amountCollateralExcess, BORROWER, receiver);

        vm.stopPrank();

        assertEq(blue.collateral(id, BORROWER), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(receiver), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral, "blue balance");
    }

    function testWithdrawCollateralOnBehalf(
        uint256 amountCollateral,
        uint256 amountCollateralExcess,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(blue));
        vm.assume(receiver != address(0) && receiver != address(blue));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        amountCollateralExcess = bound(amountCollateralExcess, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(onBehalf, amountCollateral + amountCollateralExcess);

        vm.startPrank(onBehalf);

        collateralAsset.approve(address(blue), amountCollateral + amountCollateralExcess);
        blue.supplyCollateral(market, amountCollateral + amountCollateralExcess, onBehalf, hex"");
        blue.setAuthorization(BORROWER, true);
        blue.borrow(market, amountBorrowed, onBehalf, onBehalf);
        vm.stopPrank();

        vm.prank(BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.WithdrawCollateral(id, BORROWER, onBehalf, receiver, amountCollateralExcess);
        blue.withdrawCollateral(market, amountCollateralExcess, onBehalf, receiver);

        assertEq(blue.collateral(id, onBehalf), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(receiver), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral, "blue balance");
    }
}
