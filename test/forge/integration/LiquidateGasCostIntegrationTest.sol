// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract LiquidateGasCostIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;

    uint256 amountSupplied;
    uint256 amountCollateral;
    uint256 amountBorrowed;
    uint256 priceCollateral;
    uint256 sharesRepaid;

    function setUp() public override {
        super.setUp();

        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundUnhealthyPosition(MIN_TEST_AMOUNT, MIN_TEST_AMOUNT, 1 ether);

        vm.assume(amountCollateral > 1);

        uint256 liquidationIncentiveFactor = _liquidationIncentiveFactor(marketParams.lltv);
        uint256 expectedRepaid =
            amountCollateral.mulDivUp(priceCollateral, ORACLE_PRICE_SCALE).wDivUp(liquidationIncentiveFactor);

        uint256 minBorrowed = Math.max(expectedRepaid, amountBorrowed);
        amountBorrowed = bound(amountBorrowed, minBorrowed, Math.max(minBorrowed, MAX_TEST_AMOUNT));

        amountSupplied = bound(amountSupplied, amountBorrowed, Math.max(amountBorrowed, MAX_TEST_AMOUNT));
        _supply(amountSupplied);

        loanToken.setBalance(LIQUIDATOR, amountBorrowed);
        collateralToken.setBalance(BORROWER, amountCollateral);

        oracle.setPrice(type(uint256).max / amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(priceCollateral);
    }

    function testLiquidatePartially() public {
        vm.prank(LIQUIDATOR);
        morpho.liquidate(marketParams, BORROWER, amountCollateral / 2, 0, hex"");
        assertGt(morpho.borrowShares(id, BORROWER), 0, "borrow shares");
    }

    function testLiquidateRealizeBadDebt() public {
        vm.prank(LIQUIDATOR);
        morpho.liquidate(marketParams, BORROWER, amountCollateral, 0, hex"");
        assertEq(morpho.borrowShares(id, BORROWER), 0, "borrow shares");
    }
}
