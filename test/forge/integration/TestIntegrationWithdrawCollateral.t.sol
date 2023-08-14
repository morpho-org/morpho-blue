// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationWithdrawCollateralTest is BaseTest {
    using MathLib for uint256;

    function testWithdrawCollateralMarketNotCreated(Market memory marketFuzz, address supplier, address receiver)
        public
    {
        vm.assume(neq(marketFuzz, market) && receiver != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdrawCollateral(marketFuzz, 1, supplier, receiver);
    }

    function testWithdrawCollateralZeroAmount(address supplier, address receiver, uint256 amount) public {
        vm.assume(supplier != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(morpho), amount);
        morpho.supplyCollateral(market, amount, supplier, hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.withdrawCollateral(market, 0, supplier, receiver);
        vm.stopPrank();
    }

    function testWithdrawCollateralToZeroAddress(address supplier, uint256 amount) public {
        vm.assume(supplier != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(market, amount, supplier, hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdrawCollateral(market, amount, supplier, address(0));
        vm.stopPrank();
    }

    function testWithdrawCollateralUnauthorized(address supplier, address attacker, address receiver, uint256 amount)
        public
    {
        vm.assume(supplier != attacker && supplier != address(0) && receiver != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(supplier, amount);

        vm.startPrank(supplier);
        collateralAsset.approve(address(morpho), amount);
        morpho.supplyCollateral(market, amount, supplier, hex"");
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdrawCollateral(market, amount, supplier, receiver);
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

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        morpho.withdrawCollateral(market, amountCollateral, BORROWER, BORROWER);
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
        vm.assume(receiver != address(0) && receiver != address(morpho));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        amountCollateralExcess = bound(amountCollateralExcess, 1, MAX_TEST_AMOUNT);

        oracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral + amountCollateralExcess);

        vm.startPrank(BORROWER);

        morpho.supplyCollateral(market, amountCollateral + amountCollateralExcess, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.WithdrawCollateral(id, BORROWER, BORROWER, receiver, amountCollateralExcess);
        morpho.withdrawCollateral(market, amountCollateralExcess, BORROWER, receiver);

        vm.stopPrank();

        assertEq(morpho.collateral(id, BORROWER), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(receiver), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(address(morpho)), amountCollateral, "morpho balance");
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
        vm.assume(onBehalf != address(0) && onBehalf != address(morpho));
        vm.assume(receiver != address(0) && receiver != address(morpho));

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _provideLiquidity(amountSupplied);

        oracle.setPrice(priceCollateral);

        amountCollateralExcess = bound(amountCollateralExcess, 1, MAX_TEST_AMOUNT);

        collateralAsset.setBalance(onBehalf, amountCollateral + amountCollateralExcess);

        vm.startPrank(onBehalf);

        collateralAsset.approve(address(morpho), amountCollateral + amountCollateralExcess);
        morpho.supplyCollateral(market, amountCollateral + amountCollateralExcess, onBehalf, hex"");
        morpho.setAuthorization(BORROWER, true);
        morpho.borrow(market, amountBorrowed, 0, onBehalf, onBehalf);
        vm.stopPrank();

        vm.prank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.WithdrawCollateral(id, BORROWER, onBehalf, receiver, amountCollateralExcess);
        morpho.withdrawCollateral(market, amountCollateralExcess, onBehalf, receiver);

        assertEq(morpho.collateral(id, onBehalf), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(receiver), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(address(morpho)), amountCollateral, "morpho balance");
    }
}
