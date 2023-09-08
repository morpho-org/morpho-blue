// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract CallbacksIntegrationTest is
    BaseTest,
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback,
    IMorphoFlashLoanCallback
{
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using MarketParamsLib for MarketParams;

    // Callback functions.

    function onMorphoSupply(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            loanableToken.approve(address(morpho), amount);
        }
    }

    function onMorphoSupplyCollateral(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCollateralCallback.selector) {
            collateralToken.approve(address(morpho), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toBorrow = abi.decode(data, (uint256));
            collateralToken.setBalance(address(this), amount);
            morpho.borrow(marketParams, toBorrow, 0, address(this), address(this));
        }
    }

    function onMorphoRepay(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testRepayCallback.selector) {
            loanableToken.approve(address(morpho), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toWithdraw = abi.decode(data, (uint256));
            morpho.withdrawCollateral(marketParams, toWithdraw, address(this), address(this));
        }
    }

    function onMorphoLiquidate(uint256 repaid, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            loanableToken.approve(address(morpho), repaid);
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testFlashLoan.selector) {
            assertEq(loanableToken.balanceOf(address(this)), amount);
            loanableToken.approve(address(morpho), amount);
        }
    }

    // Tests.

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        loanableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        morpho.flashLoan(address(loanableToken), amount, abi.encode(this.testFlashLoan.selector, hex""));

        assertEq(loanableToken.balanceOf(address(morpho)), amount, "balanceOf");
    }

    function testFlashLoanShouldRevertIfNotReimbursed(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        loanableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        loanableToken.approve(address(morpho), 0);

        vm.expectRevert(bytes(ErrorsLib.TRANSFER_FROM_FAILED));
        morpho.flashLoan(
            address(loanableToken), amount, abi.encode(this.testFlashLoanShouldRevertIfNotReimbursed.selector, hex"")
        );
    }

    function testSupplyCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        loanableToken.setBalance(address(this), amount);
        loanableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supply(marketParams, amount, 0, address(this), hex"");
        morpho.supply(marketParams, amount, 0, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(address(this), amount);
        collateralToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supplyCollateral(marketParams, amount, address(this), hex"");
        morpho.supplyCollateral(
            marketParams, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 loanableAmount) public {
        loanableAmount = bound(loanableAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, loanableAmount,) =
            _boundHealthyPosition(0, loanableAmount, IOracle(marketParams.oracle).price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        loanableToken.setBalance(address(this), loanableAmount);
        collateralToken.setBalance(address(this), collateralAmount);

        morpho.supply(marketParams, loanableAmount, 0, address(this), hex"");
        morpho.supplyCollateral(marketParams, collateralAmount, address(this), hex"");
        morpho.borrow(marketParams, loanableAmount, 0, address(this), address(this));

        loanableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.repay(marketParams, loanableAmount, 0, address(this), hex"");
        morpho.repay(marketParams, loanableAmount, 0, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 loanableAmount) public {
        loanableAmount = bound(loanableAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, loanableAmount,) =
            _boundHealthyPosition(0, loanableAmount, IOracle(marketParams.oracle).price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        loanableToken.setBalance(address(this), loanableAmount);
        collateralToken.setBalance(address(this), collateralAmount);

        morpho.supply(marketParams, loanableAmount, 0, address(this), hex"");
        morpho.supplyCollateral(marketParams, collateralAmount, address(this), hex"");
        morpho.borrow(marketParams, loanableAmount, 0, address(this), address(this));

        oracle.setPrice(0.99e18);

        loanableToken.setBalance(address(this), loanableAmount);
        loanableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.liquidate(marketParams, address(this), collateralAmount, 0, hex"");
        morpho.liquidate(
            marketParams, address(this), collateralAmount, 0, abi.encode(this.testLiquidateCallback.selector, hex"")
        );
    }

    function testFlashActions(uint256 loanableAmount) public {
        loanableAmount = bound(loanableAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, loanableAmount,) =
            _boundHealthyPosition(0, loanableAmount, IOracle(marketParams.oracle).price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        loanableToken.setBalance(address(this), loanableAmount);
        morpho.supply(marketParams, loanableAmount, 0, address(this), hex"");

        morpho.supplyCollateral(
            marketParams,
            collateralAmount,
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(loanableAmount))
        );
        assertGt(morpho.borrowShares(marketParams.id(), address(this)), 0, "no borrow");

        morpho.repay(
            marketParams,
            loanableAmount,
            0,
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(collateralAmount))
        );
        assertEq(morpho.collateral(marketParams.id(), address(this)), 0, "no withdraw collateral");
    }
}
