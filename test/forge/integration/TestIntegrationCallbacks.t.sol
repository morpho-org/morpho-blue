// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";
import "src/interfaces/IMorphoCallbacks.sol";

contract IntegrationCallbacksTest is
    BaseTest,
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback,
    IMorphoFlashLoanCallback
{
    using MarketLib for Info;
    using MathLib for uint256;
    using MorphoLib for Morpho;

    // Callback functions.

    function onMorphoSupply(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            borrowableToken.approve(address(morpho), amount);
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
            morpho.borrow(market, toBorrow, 0, address(this), address(this));
        }
    }

    function onMorphoRepay(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testRepayCallback.selector) {
            borrowableToken.approve(address(morpho), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toWithdraw = abi.decode(data, (uint256));
            morpho.withdrawCollateral(market, toWithdraw, address(this), address(this));
        }
    }

    function onMorphoLiquidate(uint256 repaid, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            borrowableToken.approve(address(morpho), repaid);
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes calldata) external {
        borrowableToken.approve(address(morpho), amount);
    }

    // Tests.

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        morpho.flashLoan(address(borrowableToken), amount, hex"");

        assertEq(borrowableToken.balanceOf(address(morpho)), amount, "balanceOf");
    }

    function testSupplyCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        borrowableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supply(market, amount, 0, address(this), hex"");
        morpho.supply(market, amount, 0, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(address(this), amount);
        collateralToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supplyCollateral(market, amount, address(this), hex"");
        morpho.supplyCollateral(
            market, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 borrowableAmount) public {
        borrowableAmount = bound(borrowableAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, borrowableAmount,) =
            _boundHealthyPosition(0, borrowableAmount, IOracle(market.oracle).price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        borrowableToken.setBalance(address(this), borrowableAmount);
        collateralToken.setBalance(address(this), collateralAmount);

        morpho.supply(market, borrowableAmount, 0, address(this), hex"");
        morpho.supplyCollateral(market, collateralAmount, address(this), hex"");
        morpho.borrow(market, borrowableAmount, 0, address(this), address(this));

        borrowableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.repay(market, borrowableAmount, 0, address(this), hex"");
        morpho.repay(market, borrowableAmount, 0, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 borrowableAmount) public {
        borrowableAmount = bound(borrowableAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, borrowableAmount,) =
            _boundHealthyPosition(0, borrowableAmount, IOracle(market.oracle).price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        borrowableToken.setBalance(address(this), borrowableAmount);
        collateralToken.setBalance(address(this), collateralAmount);

        morpho.supply(market, borrowableAmount, 0, address(this), hex"");
        morpho.supplyCollateral(market, collateralAmount, address(this), hex"");
        morpho.borrow(market, borrowableAmount, 0, address(this), address(this));

        oracle.setPrice(0.99e18);

        borrowableToken.setBalance(address(this), borrowableAmount);
        borrowableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.liquidate(market, address(this), collateralAmount, hex"");
        morpho.liquidate(
            market, address(this), collateralAmount, abi.encode(this.testLiquidateCallback.selector, hex"")
        );
    }

    function testFlashActions(uint256 borrowableAmount) public {
        borrowableAmount = bound(borrowableAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 collateralAmount;
        (collateralAmount, borrowableAmount,) =
            _boundHealthyPosition(0, borrowableAmount, IOracle(market.oracle).price());

        oracle.setPrice(ORACLE_PRICE_SCALE);

        borrowableToken.setBalance(address(this), borrowableAmount);
        morpho.supply(market, borrowableAmount, 0, address(this), hex"");

        morpho.supplyCollateral(
            market,
            collateralAmount,
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(borrowableAmount))
        );
        assertGt(morpho.borrowShares(market.id(), address(this)), 0, "no borrow");

        morpho.repay(
            market,
            borrowableAmount,
            0,
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(collateralAmount))
        );
        assertEq(morpho.collateral(market.id(), address(this)), 0, "no withdraw collateral");
    }
}
