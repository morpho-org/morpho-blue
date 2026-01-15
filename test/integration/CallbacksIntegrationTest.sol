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
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    // Callback functions.

    function onMorphoSupply(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            loanToken.approve(address(morpho), amount);
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
            loanToken.approve(address(morpho), amount);
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
            loanToken.approve(address(morpho), repaid);
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testFlashLoan.selector) {
            assertEq(loanToken.balanceOf(address(this)), amount);
            loanToken.approve(address(morpho), amount);
        }
    }

    // Tests.

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        loanToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        morpho.flashLoan(address(loanToken), amount, abi.encode(this.testFlashLoan.selector, hex""));

        assertEq(loanToken.balanceOf(address(morpho)), amount, "balanceOf");
    }

    function testFlashLoanZero() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ASSETS));
        morpho.flashLoan(address(loanToken), 0, abi.encode(this.testFlashLoan.selector, hex""));
    }

    function testFlashLoanShouldRevertIfNotReimbursed(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        loanToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        loanToken.approve(address(morpho), 0);

        vm.expectRevert(bytes(ErrorsLib.TRANSFER_FROM_REVERTED));
        morpho.flashLoan(
            address(loanToken), amount, abi.encode(this.testFlashLoanShouldRevertIfNotReimbursed.selector, hex"")
        );
    }

    function testSupplyCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        loanToken.setBalance(address(this), amount);
        loanToken.approve(address(morpho), 0);

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

    function testRepayCallback(uint256 loanAmount) public {
        loanAmount = bound(loanAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, loanAmount,) = _boundHealthyPosition(0, loanAmount, oracle.price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        loanToken.setBalance(address(this), loanAmount);
        collateralToken.setBalance(address(this), collateralAmount);

        morpho.supply(marketParams, loanAmount, 0, address(this), hex"");
        morpho.supplyCollateral(marketParams, collateralAmount, address(this), hex"");
        morpho.borrow(marketParams, loanAmount, 0, address(this), address(this));

        loanToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.repay(marketParams, loanAmount, 0, address(this), hex"");
        morpho.repay(marketParams, loanAmount, 0, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 loanAmount) public {
        loanAmount = bound(loanAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, loanAmount,) = _boundHealthyPosition(0, loanAmount, oracle.price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        loanToken.setBalance(address(this), loanAmount);
        collateralToken.setBalance(address(this), collateralAmount);

        morpho.supply(marketParams, loanAmount, 0, address(this), hex"");
        morpho.supplyCollateral(marketParams, collateralAmount, address(this), hex"");
        morpho.borrow(marketParams, loanAmount, 0, address(this), address(this));

        oracle.setPrice(0.99e18);

        loanToken.setBalance(address(this), loanAmount);
        loanToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.liquidate(marketParams, address(this), collateralAmount, 0, hex"");
        morpho.liquidate(
            marketParams, address(this), collateralAmount, 0, abi.encode(this.testLiquidateCallback.selector, hex"")
        );
    }

    function testFlashActions(uint256 loanAmount) public {
        loanAmount = bound(loanAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, loanAmount,) = _boundHealthyPosition(0, loanAmount, oracle.price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        loanToken.setBalance(address(this), loanAmount);
        morpho.supply(marketParams, loanAmount, 0, address(this), hex"");

        morpho.supplyCollateral(
            marketParams,
            collateralAmount,
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(loanAmount))
        );
        assertGt(morpho.borrowShares(marketParams.id(), address(this)), 0, "no borrow");

        morpho.repay(
            marketParams,
            loanAmount,
            0,
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(collateralAmount))
        );
        assertEq(morpho.collateral(marketParams.id(), address(this)), 0, "no withdraw collateral");
    }
}
