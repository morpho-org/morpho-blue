// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";
import "src/interfaces/IBlueCallbacks.sol";

contract IntegrationCallbacksTest is
    BaseTest,
    IBlueLiquidateCallback,
    IBlueRepayCallback,
    IBlueSupplyCallback,
    IBlueSupplyCollateralCallback,
    IBlueFlashLoanCallback
{
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    // Callback functions.

    function onBlueSupply(uint256 amount, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            borrowableAsset.approve(address(blue), amount);
        }
    }

    function onBlueSupplyCollateral(uint256 amount, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCollateralCallback.selector) {
            collateralAsset.approve(address(blue), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toBorrow = abi.decode(data, (uint256));
            collateralAsset.setBalance(address(this), amount);
            blue.borrow(market, toBorrow, 0, address(this), address(this));
        }
    }

    function onBlueRepay(uint256 amount, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testRepayCallback.selector) {
            borrowableAsset.approve(address(blue), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toWithdraw = abi.decode(data, (uint256));
            blue.withdrawCollateral(market, toWithdraw, address(this), address(this));
        }
    }

    function onBlueLiquidate(uint256, uint256 repaid, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            borrowableAsset.approve(address(blue), repaid);
        }
    }

    function onBlueFlashLoan(address token, uint256 amount, bytes calldata) external {
        ERC20(token).approve(address(blue), amount);
    }

    // Tests.

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, 0, address(this), hex"");

        blue.flashLoan(address(borrowableAsset), amount, bytes(""));

        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "balanceOf");
    }

    function testSupplyCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        borrowableAsset.setBalance(address(this), amount);
        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supply(market, amount, 0, address(this), hex"");
        blue.supply(market, amount, 0, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralAsset.setBalance(address(this), amount);
        collateralAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supplyCollateral(market, amount, address(this), hex"");
        blue.supplyCollateral(
            market, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 amount) public {
        amount = bound(amount, MIN_COLLATERAL_PRICE, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        collateralAsset.setBalance(address(this), amount.wDivUp(LLTV));

        blue.supply(market, amount, 0, address(this), hex"");
        blue.supplyCollateral(market, amount.wDivUp(LLTV), address(this), hex"");
        blue.borrow(market, amount, 0, address(this), address(this));

        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.repay(market, amount, 0, address(this), hex"");
        blue.repay(market, amount, 0, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        oracle.setPrice(1e18);
        borrowableAsset.setBalance(address(this), amount);
        collateralAsset.setBalance(address(this), amount);
        blue.supply(market, amount, 0, address(this), hex"");
        blue.supplyCollateral(market, amount, address(this), hex"");
        blue.borrow(market, amount.wMulDown(LLTV), 0, address(this), address(this));

        oracle.setPrice(0.99e18);

        uint256 toSeize = amount.wMulDown(LLTV);

        borrowableAsset.setBalance(address(this), toSeize);
        borrowableAsset.approve(address(blue), 0);
        vm.expectRevert();
        blue.liquidate(market, address(this), toSeize, hex"");
        blue.liquidate(market, address(this), toSeize, abi.encode(this.testLiquidateCallback.selector, hex""));
    }

    function testFlashActions(uint256 amount) public {
        amount = bound(amount, 10, MAX_TEST_AMOUNT);
        oracle.setPrice(1e18);
        uint256 toBorrow = amount.wMulDown(LLTV);

        borrowableAsset.setBalance(address(this), toBorrow);
        blue.supply(market, toBorrow, 0, address(this), hex"");

        blue.supplyCollateral(
            market, amount, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(blue.borrowShares(market.id(), address(this)), 0, "no borrow");

        blue.repay(market, toBorrow, 0, address(this), abi.encode(this.testFlashActions.selector, abi.encode(amount)));
        assertEq(blue.collateral(market.id(), address(this)), 0, "no withdraw collateral");
    }
}
