// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationWithdrawCollateralTest is BlueBaseTest {
    using FixedPointMathLib for uint256;

    function testWithdrawCollateralUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdrawCollateral(marketFuzz, 1, address(this), address(this));
    }

    function testWithdrawCollateralZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.withdrawCollateral(market, 0, address(this), address(this));
    }

    function testWithdrawCollateralToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdrawCollateral(market, amount, address(this), address(0));
    }

    function testWithdrawCollateralUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, address(this), hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdrawCollateral(market, amount, address(this), address(this));
    }

    function testWithdrawCollateralUnhealthyPosition(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);
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

        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);
        _provideLiquidity(amountSupplied);

        amountCollateralExcess = bound(amountCollateralExcess, 1, 2 ** 64);

        borrowableOracle.setPrice(FixedPointMathLib.WAD);
        collateralOracle.setPrice(priceCollateral);

        collateralAsset.setBalance(BORROWER, amountCollateral + amountCollateralExcess);

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral + amountCollateralExcess, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
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

        amountSupplied = bound(amountSupplied, amountBorrowed, 2 ** 64);
        _provideLiquidity(amountSupplied);

        amountCollateralExcess = bound(amountCollateralExcess, 1, 2 ** 64);

        collateralAsset.setBalance(onBehalf, amountCollateral + amountCollateralExcess);

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(blue), amountCollateral + amountCollateralExcess);
        blue.supplyCollateral(market, amountCollateral + amountCollateralExcess, onBehalf, hex"");
        blue.setAuthorization(BORROWER, true);
        blue.borrow(market, amountBorrowed, onBehalf, onBehalf);
        vm.stopPrank();

        vm.prank(BORROWER);
        blue.withdrawCollateral(market, amountCollateralExcess, onBehalf, receiver);

        assertEq(blue.collateral(id, onBehalf), amountCollateral, "collateral balance");
        assertEq(collateralAsset.balanceOf(receiver), amountCollateralExcess, "lender balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountCollateral, "blue balance");
    }
}
