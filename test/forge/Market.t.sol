// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Market.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";

contract MarketTest is Test {
    using MathLib for uint;

    address private constant borrower = address(1234);

    Market private market;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;

    function setUp() public {
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();
        market = new Market(
            address(borrowableAsset),
            address(collateralAsset),
            address(borrowableOracle),
            address(collateralOracle)
        );

        // We set the price of the borrowable asset to zero so that borrowers
        // don't need to deposit any collateral.
        borrowableOracle.setPrice(0);
        collateralOracle.setPrice(1e18);

        borrowableAsset.approve(address(market), type(uint).max);
        collateralAsset.approve(address(market), type(uint).max);
        vm.startPrank(borrower);
        borrowableAsset.approve(address(market), type(uint).max);
        collateralAsset.approve(address(market), type(uint).max);
        vm.stopPrank();
    }

    function invariantParams() public {
        assertEq(market.borrowableAsset(), address(borrowableAsset));
        assertEq(market.collateralAsset(), address(collateralAsset));
        assertEq(market.borrowableOracle(), address(borrowableOracle));
        assertEq(market.collateralOracle(), address(collateralOracle));
    }

    function invariantLiquidity() public {
        for (uint bucket; bucket < N; bucket++) {
            assertLe(market.totalBorrow(bucket), market.totalSupply(bucket));
        }
    }

    function testDeposit(uint amount, uint bucket) public {
        amount = bound(amount, 1, 2 ** 64);
        vm.assume(bucket < N);

        borrowableAsset.setBalance(address(this), amount);
        market.modifyDeposit(int(amount), bucket);

        assertEq(market.supplyShare(address(this), bucket), 1e18);
        assertEq(borrowableAsset.balanceOf(address(this)), 0);
        assertEq(borrowableAsset.balanceOf(address(market)), amount);
    }

    function testBorrow(uint amountLent, uint amountBorrowed, uint bucket) public {
        amountLent = bound(amountLent, 0, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 0, 2 ** 64);
        vm.assume(bucket < N);

        borrowableAsset.setBalance(address(this), amountLent);
        market.modifyDeposit(int(amountLent), bucket);

        if (amountBorrowed == 0) {
            market.modifyBorrow(int(amountBorrowed), bucket);
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(borrower);
            vm.expectRevert("not enough liquidity");
            market.modifyBorrow(int(amountBorrowed), bucket);
            return;
        }

        vm.prank(borrower);
        market.modifyBorrow(int(amountBorrowed), bucket);

        assertEq(market.borrowShare(borrower, bucket), 1e18);
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed);
        assertEq(borrowableAsset.balanceOf(address(market)), amountLent - amountBorrowed);
    }

    function testWithdraw(uint amountLent, uint amountWithdrawn, uint amountBorrowed, uint bucket) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        vm.assume(bucket < N);
        vm.assume(amountLent >= amountBorrowed);
        vm.assume(int(amountWithdrawn) >= 0);

        borrowableAsset.setBalance(address(this), amountLent);
        market.modifyDeposit(int(amountLent), bucket);

        vm.prank(borrower);
        market.modifyBorrow(int(amountBorrowed), bucket);

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert("not enough liquidity");
            }
            market.modifyDeposit(-int(amountWithdrawn), bucket);
            return;
        }

        market.modifyDeposit(-int(amountWithdrawn), bucket);

        assertApproxEqAbs(
            market.supplyShare(address(this), bucket), (amountLent - amountWithdrawn) * 1e18 / amountLent, 1e3
        );
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn);
        assertEq(borrowableAsset.balanceOf(address(market)), amountLent - amountBorrowed - amountWithdrawn);
    }

    function testCollateralRequirements(
        uint amountCollateral,
        uint amountBorrowed,
        uint priceCollateral,
        uint priceBorrowable,
        uint bucket
    ) public {
        amountBorrowed = bound(amountBorrowed, 0, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 0, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);
        vm.assume(bucket < N);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountBorrowed);
        collateralAsset.setBalance(borrower, amountCollateral);

        market.modifyDeposit(int(amountBorrowed), bucket);

        vm.prank(borrower);
        market.modifyCollateral(int(amountCollateral), bucket);

        uint collateralValue = amountCollateral.wMul(priceCollateral);
        uint borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.wMul(bucketToLLTV(bucket)))) {
            vm.prank(borrower);
            market.modifyBorrow(int(amountBorrowed), bucket);
        } else {
            vm.prank(borrower);
            vm.expectRevert("not enough collateral");
            market.modifyBorrow(int(amountBorrowed), bucket);
        }
    }

    function testRepay(uint amountLent, uint amountBorrowed, uint amountRepaid, uint bucket) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 0, amountBorrowed);
        vm.assume(bucket < N);

        borrowableAsset.setBalance(address(this), amountLent);
        market.modifyDeposit(int(amountLent), bucket);

        vm.startPrank(borrower);
        market.modifyBorrow(int(amountBorrowed), bucket);
        market.modifyBorrow(-int(amountRepaid), bucket);
        vm.stopPrank();

        assertApproxEqAbs(
            market.borrowShare(borrower, bucket), (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed, 1e3
        );
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed - amountRepaid);
        assertEq(borrowableAsset.balanceOf(address(market)), amountLent - amountBorrowed + amountRepaid);
    }

    function testDepositCollateral(uint amount, uint bucket) public {
        vm.assume(bucket < N);
        vm.assume(int(amount) >= 0);

        collateralAsset.setBalance(address(this), amount);
        market.modifyCollateral(int(amount), bucket);

        assertEq(market.collateral(address(this), bucket), amount);
        assertEq(collateralAsset.balanceOf(address(this)), 0);
        assertEq(collateralAsset.balanceOf(address(market)), amount);
    }

    function testWithdrawCollateral(uint amountDeposited, uint amountWithdrawn, uint bucket) public {
        vm.assume(bucket < N);
        vm.assume(int(amountDeposited) > 0);
        vm.assume(int(amountWithdrawn) > 0);

        collateralAsset.setBalance(address(this), amountDeposited);
        market.modifyCollateral(int(amountDeposited), bucket);

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert("negative");
            market.modifyCollateral(-int(amountWithdrawn), bucket);
            return;
        }

        market.modifyCollateral(-int(amountWithdrawn), bucket);

        assertEq(market.collateral(address(this), bucket), amountDeposited - amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(this)), amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(market)), amountDeposited - amountWithdrawn);
    }

    function testTwoUsersSupply(uint firstAmount, uint secondAmount, uint bucket) public {
        vm.assume(bucket < N);
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 0, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        market.modifyDeposit(int(firstAmount), bucket);

        borrowableAsset.setBalance(borrower, secondAmount);
        vm.prank(borrower);
        market.modifyDeposit(int(secondAmount), bucket);

        assertEq(market.supplyShare(address(this), bucket), 1e18);
        assertEq(market.supplyShare(borrower, bucket), secondAmount * 1e18 / firstAmount);
    }

    function testModifyDepositUnknownBucket(uint bucket) public {
        vm.assume(bucket > N);
        vm.expectRevert("unknown bucket");
        market.modifyDeposit(1, bucket);
    }

    function testModifyBorrowUnknownBucket(uint bucket) public {
        vm.assume(bucket > N);
        vm.expectRevert("unknown bucket");
        market.modifyBorrow(1, bucket);
    }

    function testModifyCollateralUnknownBucket(uint bucket) public {
        vm.assume(bucket > N);
        vm.expectRevert("unknown bucket");
        market.modifyCollateral(1, bucket);
    }

    function testWithdrawEmptyMarket(int amount, uint bucket) public {
        vm.assume(bucket < N);
        vm.assume(amount < 0);
        vm.expectRevert(stdError.divisionError);
        market.modifyDeposit(amount, bucket);
    }

    function testRepayEmptyMarket(int amount, uint bucket) public {
        vm.assume(bucket < N);
        vm.assume(amount < 0);
        vm.expectRevert(stdError.divisionError);
        market.modifyBorrow(amount, bucket);
    }

    function testWithdrawCollateralEmptyMarket(int amount, uint bucket) public {
        vm.assume(bucket < N);
        vm.assume(amount < 0);
        vm.expectRevert("negative");
        market.modifyCollateral(amount, bucket);
    }
}
