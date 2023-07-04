// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Market.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";

contract BlueTest is Test {
    using MathLib for uint;

    address private constant borrower = address(1234);
    uint private constant lLTV = 0.8 ether;

    Blue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    Market public market;
    Id public id;

    function setUp() public {
        // Create Blue.
        blue = new Blue();

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();
        market = Market(
            IERC20(address(borrowableAsset)), IERC20(address(collateralAsset)), borrowableOracle, collateralOracle, lLTV
        );
        id = Id.wrap(keccak256(abi.encode(market)));

        blue.createMarket(market);

        // We set the price of the borrowable asset to zero so that borrowers
        // don't need to deposit any collateral.
        borrowableOracle.setPrice(0);
        collateralOracle.setPrice(1e18);

        borrowableAsset.approve(address(blue), type(uint).max);
        collateralAsset.approve(address(blue), type(uint).max);
        vm.startPrank(borrower);
        borrowableAsset.approve(address(blue), type(uint).max);
        collateralAsset.approve(address(blue), type(uint).max);
        vm.stopPrank();
    }

    function invariantLiquidity() public {
        assertLe(blue.totalBorrow(id), blue.totalSupply(id));
    }

    function testSupply(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount);

        assertEq(blue.supplyShare(id, address(this)), 1e18);
        assertEq(borrowableAsset.balanceOf(address(this)), 0);
        assertEq(borrowableAsset.balanceOf(address(blue)), amount);
    }

    function testBorrow(uint amountLent, uint amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent);

        if (amountBorrowed == 0) {
            blue.borrow(market, amountBorrowed);
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(borrower);
            vm.expectRevert("not enough liquidity");
            blue.borrow(market, amountBorrowed);
            return;
        }

        vm.prank(borrower);
        blue.borrow(market, amountBorrowed);

        assertEq(blue.borrowShare(id, borrower), 1e18);
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed);
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed);
    }

    function testWithdraw(uint amountLent, uint amountWithdrawn, uint amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent);

        vm.prank(borrower);
        blue.borrow(market, amountBorrowed);

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert("not enough liquidity");
            }
            blue.withdraw(market, amountWithdrawn);
            return;
        }

        blue.withdraw(market, amountWithdrawn);

        assertApproxEqAbs(blue.supplyShare(id, address(this)), (amountLent - amountWithdrawn) * 1e18 / amountLent, 1e3);
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn);
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed - amountWithdrawn);
    }

    function testCollateralRequirements(
        uint amountCollateral,
        uint amountBorrowed,
        uint priceCollateral,
        uint priceBorrowable
    ) public {
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountBorrowed);
        collateralAsset.setBalance(borrower, amountCollateral);

        blue.supply(market, amountBorrowed);

        vm.prank(borrower);
        blue.supplyCollateral(market, amountCollateral);

        uint collateralValue = amountCollateral.wMul(priceCollateral);
        uint borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.wMul(lLTV))) {
            vm.prank(borrower);
            blue.borrow(market, amountBorrowed);
        } else {
            vm.prank(borrower);
            vm.expectRevert("not enough collateral");
            blue.borrow(market, amountBorrowed);
        }
    }

    function testRepay(uint amountLent, uint amountBorrowed, uint amountRepaid) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent);

        vm.startPrank(borrower);
        blue.borrow(market, amountBorrowed);
        blue.repay(market, amountRepaid);
        vm.stopPrank();

        assertApproxEqAbs(blue.borrowShare(id, borrower), (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed, 1e3);
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed - amountRepaid);
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid);
    }

    function testSupplyCollateral(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount);

        assertEq(blue.collateral(id, address(this)), amount);
        assertEq(collateralAsset.balanceOf(address(this)), 0);
        assertEq(collateralAsset.balanceOf(address(blue)), amount);
    }

    function testWithdrawCollateral(uint amountDeposited, uint amountWithdrawn) public {
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        blue.supplyCollateral(market, amountDeposited);

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(market, amountWithdrawn);
            return;
        }

        blue.withdrawCollateral(market, amountWithdrawn);

        assertEq(blue.collateral(id, address(this)), amountDeposited - amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(this)), amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(blue)), amountDeposited - amountWithdrawn);
    }

    function testTwoUsersSupply(uint firstAmount, uint secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        blue.supply(market, firstAmount);

        borrowableAsset.setBalance(borrower, secondAmount);
        vm.prank(borrower);
        blue.supply(market, secondAmount);

        assertEq(blue.supplyShare(id, address(this)), 1e18);
        assertEq(blue.supplyShare(id, borrower), secondAmount * 1e18 / firstAmount);
    }

    function testSupplyUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));
        vm.expectRevert("unknown market");
        blue.supply(marketFuzz, 1);
    }

    function testWithdrawUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));
        vm.expectRevert("unknown market");
        blue.withdraw(marketFuzz, 1);
    }

    function testBorrowUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));
        vm.expectRevert("unknown market");
        blue.borrow(marketFuzz, 1);
    }

    function testRepayUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));
        vm.expectRevert("unknown market");
        blue.repay(marketFuzz, 1);
    }

    function testSupplyCollateralUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));
        vm.expectRevert("unknown market");
        blue.supplyCollateral(marketFuzz, 1);
    }

    function testWithdrawCollateralUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));
        vm.expectRevert("unknown market");
        blue.withdrawCollateral(marketFuzz, 1);
    }

    function testAmountZero() public {
        vm.expectRevert("zero amount");
        blue.supply(market, 0);

        vm.expectRevert("zero amount");
        blue.withdraw(market, 0);

        vm.expectRevert("zero amount");
        blue.borrow(market, 0);

        vm.expectRevert("zero amount");
        blue.repay(market, 0);

        vm.expectRevert("zero amount");
        blue.supplyCollateral(market, 0);

        vm.expectRevert("zero amount");
        blue.withdrawCollateral(market, 0);
    }

    function testWithdrawEmptyMarket(uint amount) public {
        vm.assume(amount > 0);
        vm.expectRevert(stdError.divisionError);
        blue.withdraw(market, amount);
    }

    function testRepayEmptyMarket(uint amount) public {
        vm.assume(amount > 0);
        vm.expectRevert(stdError.divisionError);
        blue.repay(market, amount);
    }

    function testWithdrawCollateralEmptyMarket(uint amount) public {
        vm.assume(amount > 0);
        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(market, amount);
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lLTV != b.lLTV;
}
