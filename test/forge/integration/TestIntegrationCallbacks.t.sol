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
    using MarketLib for Market;
    using MathLib for uint256;

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
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(address(this), amount);
        collateralToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supplyCollateral(market, amount, address(this), hex"");
        morpho.supplyCollateral(
            market, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 amount) public {
        amount = bound(amount, MIN_COLLATERAL_PRICE, MAX_TEST_AMOUNT);

        oracle.setPrice(WAD);

        borrowableToken.setBalance(address(this), amount);
        collateralToken.setBalance(address(this), amount.mulDivUp(ORACLE_PRICE_SCALE, WAD));

        morpho.supply(market, amount, 0, address(this), hex"");
        morpho.supplyCollateral(market, amount.mulDivUp(ORACLE_PRICE_SCALE, WAD), address(this), hex"");
        morpho.borrow(market, amount.wMulDown(LLTV), 0, address(this), address(this));

        borrowableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.repay(market, amount.wMulDown(LLTV), 0, address(this), hex"");
        morpho.repay(
            market, amount.wMulDown(LLTV), 0, address(this), abi.encode(this.testRepayCallback.selector, hex"")
        );
    }

    function testLiquidateCallback(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        oracle.setPrice(WAD);

        borrowableToken.setBalance(address(this), amount);
        collateralToken.setBalance(address(this), amount.mulDivUp(ORACLE_PRICE_SCALE, WAD).wDivUp(market.lltv));

        morpho.supply(market, amount, 0, address(this), hex"");
        morpho.supplyCollateral(market, amount.mulDivUp(ORACLE_PRICE_SCALE, WAD), address(this), hex"");
        morpho.borrow(market, amount.wMulDown(LLTV), 0, address(this), address(this));

        oracle.setPrice(0.99e18);

        uint256 toSeize = amount.wMulDown(LLTV);

        borrowableToken.setBalance(address(this), toSeize);
        borrowableToken.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.liquidate(market, address(this), toSeize, 0, hex"");
        morpho.liquidate(market, address(this), toSeize, 0, abi.encode(this.testLiquidateCallback.selector, hex""));
    }

    function testFlashActions(uint256 amount) public {
        amount = bound(amount, 10, MAX_TEST_AMOUNT);

        oracle.setPrice(WAD);

        uint256 toBorrow = amount.mulDivDown(WAD, ORACLE_PRICE_SCALE).wMulDown(LLTV);
        vm.assume(toBorrow != 0);

        borrowableToken.setBalance(address(this), toBorrow);
        morpho.supply(market, toBorrow, 0, address(this), hex"");

        morpho.supplyCollateral(
            market, amount, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(morpho.borrowShares(market.id(), address(this)), 0, "no borrow");

        morpho.repay(market, toBorrow, 0, address(this), abi.encode(this.testFlashActions.selector, abi.encode(amount)));
        assertEq(morpho.collateral(market.id(), address(this)), 0, "no withdraw collateral");
    }
}
