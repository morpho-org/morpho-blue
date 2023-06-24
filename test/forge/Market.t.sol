// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Market.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";

contract MarketTest is Test {
    using MathLib for uint;

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

        borrowableOracle.setPrice(0);
        collateralOracle.setPrice(1e18);
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

    function invariantLiquidity2() public {
        uint expectedMinimumBalance;
        for (uint bucket; bucket < N; bucket++) {
            expectedMinimumBalance += market.totalSupply(bucket) + market.totalBorrow(bucket);
        }
        assertGe(borrowableAsset.balanceOf(address(market)), expectedMinimumBalance);
    }

    function testDeposit(address user, uint amount, uint maxLLTV) public {
        amount = bound(amount, 1, 2 ** 64);
        vm.assume(user != address(market));
        vm.assume(maxLLTV < N);

        borrowableAsset.setBalance(user, amount);

        vm.startPrank(user);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(amount), maxLLTV);
        vm.stopPrank();

        assertEq(market.supplyShare(user, maxLLTV), 1e18, "supply balance user");
        assertEq(borrowableAsset.balanceOf(user), 0, "token balance user");
        assertEq(borrowableAsset.balanceOf(address(market)), amount, "token balance market");
    }

    function testBorrow(address lender, uint maxLLTV, uint amountLent, address borrower, uint amountBorrowed) public {
        amountLent = bound(amountLent, 0, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 0, 2 ** 64);
        vm.assume(lender != address(market));
        vm.assume(maxLLTV < N);

        borrowableAsset.setBalance(lender, amountLent);

        vm.startPrank(lender);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(amountLent), maxLLTV);
        vm.stopPrank();

        if (amountBorrowed == 0) {
            // No need to deposit any collateral as the price of the borrowed asset is 0.
            market.modifyBorrow(int(amountBorrowed), maxLLTV);
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(borrower);
            vm.expectRevert("not enough liquidity");
            // No need to deposit any collateral as the price of the borrowed asset is 0.
            market.modifyBorrow(int(amountBorrowed), maxLLTV);
            return;
        }

        vm.prank(borrower);
        // No need to deposit any collateral as the price of the borrowed asset is 0.
        market.modifyBorrow(int(amountBorrowed), maxLLTV);

        assertEq(market.borrowShare(borrower, maxLLTV), 1e18, "borrow balance borrower");
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed, "token balance borrower");
        assertEq(borrowableAsset.balanceOf(address(market)), amountLent - amountBorrowed, "token balance market");
    }

    function testWithdraw(
        address lender,
        uint maxLLTV,
        uint amountLent,
        uint amountWithdrawn,
        address borrower,
        uint amountBorrowed
    ) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        vm.assume(lender != address(market));
        vm.assume(lender != borrower);
        vm.assume(maxLLTV < N);
        vm.assume(amountLent >= amountBorrowed);
        vm.assume(int(amountWithdrawn) >= 0);

        borrowableAsset.setBalance(lender, amountLent);

        vm.startPrank(lender);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(amountLent), maxLLTV);
        vm.stopPrank();

        vm.startPrank(borrower);
        market.modifyBorrow(int(amountBorrowed), maxLLTV);
        vm.stopPrank();

        // Should revert because not enough liquidity.
        if (amountWithdrawn > amountLent - amountBorrowed) {
            vm.prank(lender);
            vm.expectRevert();
            market.modifyDeposit(-int(amountWithdrawn), maxLLTV);
            return;
        }

        vm.prank(lender);
        market.modifyDeposit(-int(amountWithdrawn), maxLLTV);

        assertApproxEqAbs(
            market.supplyShare(lender, maxLLTV),
            (amountLent - amountWithdrawn) * 1e18 / amountLent,
            1e3,
            "supply balance lender"
        );
        assertEq(borrowableAsset.balanceOf(lender), amountWithdrawn, "token balance lender");
        assertEq(
            borrowableAsset.balanceOf(address(market)),
            amountLent - amountBorrowed - amountWithdrawn,
            "token balance market"
        );
    }

    function testCollateralRequirements(
        address lender,
        address borrower,
        uint amountCollateral,
        uint amountBorrowed,
        uint priceCollateral,
        uint priceBorrowable
    ) public {
        vm.assume(lender != address(market));
        vm.assume(borrower != address(market));
        vm.assume(lender != borrower);
        amountBorrowed = bound(amountBorrowed, 0, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 0, 2 ** 64);
        priceCollateral = bound(priceCollateral, 1, 2 ** 64);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(lender, amountBorrowed);
        collateralAsset.setBalance(borrower, amountCollateral);

        vm.startPrank(lender);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(amountBorrowed), 1);
        vm.stopPrank();

        vm.startPrank(borrower);
        collateralAsset.approve(address(market), type(uint).max);
        market.modifyCollateral(int(amountCollateral));
        vm.stopPrank();

        uint collateralValue = amountCollateral.wMul(priceCollateral);
        uint borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue.wDiv(bucketToLLTV(1)) <= collateralValue)) {
            vm.prank(borrower);
            market.modifyBorrow(int(amountBorrowed), 1);
        } else {
            vm.prank(borrower);
            vm.expectRevert("not enough collateral");
            market.modifyBorrow(int(amountBorrowed), 1);
        }
    }

    function testRepay(
        address lender,
        uint maxLLTV,
        uint amountLent,
        address borrower,
        uint amountBorrowed,
        uint amountRepaid
    ) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 0, amountBorrowed);
        vm.assume(lender != address(market));
        vm.assume(lender != borrower);
        vm.assume(maxLLTV < N);

        borrowableAsset.setBalance(lender, amountLent);

        vm.startPrank(lender);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(amountLent), maxLLTV);
        vm.stopPrank();

        vm.startPrank(borrower);
        market.modifyBorrow(int(amountBorrowed), maxLLTV);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyBorrow(-int(amountRepaid), maxLLTV);
        vm.stopPrank();

        assertApproxEqAbs(
            market.borrowShare(borrower, maxLLTV),
            (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed,
            1e3,
            "borrow balance borrower"
        );
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed - amountRepaid, "token balance borrower");
        assertEq(
            borrowableAsset.balanceOf(address(market)),
            amountLent - amountBorrowed + amountRepaid,
            "token balance market"
        );
    }

    function testDepositCollateral(address user, uint amount) public {
        collateralAsset.setBalance(user, amount);
        vm.assume(int(amount) >= 0);
        vm.assume(user != address(market));

        vm.startPrank(user);
        collateralAsset.approve(address(market), type(uint).max);
        market.modifyCollateral(int(amount));
        vm.stopPrank();

        assertEq(market.collateral(user), amount);
        assertEq(collateralAsset.balanceOf(user), 0);
        assertEq(collateralAsset.balanceOf(address(market)), amount);
    }

    function testWithdrawCollateral(address user, uint amountDeposited, uint amountWithdrawn) public {
        vm.assume(amountDeposited >= amountWithdrawn);
        vm.assume(int(amountDeposited) >= 0);
        vm.assume(user != address(market));

        collateralAsset.setBalance(user, amountDeposited);

        vm.startPrank(user);
        collateralAsset.approve(address(market), type(uint).max);
        market.modifyCollateral(int(amountDeposited));
        vm.stopPrank();

        vm.prank(user);
        market.modifyCollateral(-int(amountWithdrawn));

        assertEq(market.collateral(user), amountDeposited - amountWithdrawn);
        assertEq(collateralAsset.balanceOf(user), amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(market)), amountDeposited - amountWithdrawn);
    }

    function testTwoUsersSupply(
        address firstUser,
        uint firstAmount,
        uint maxLLTV,
        address secondUser,
        uint secondAmount
    ) public {
        vm.assume(firstUser != secondUser);
        vm.assume(firstUser != address(market));
        vm.assume(secondUser != address(market));
        vm.assume(maxLLTV < N);
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 0, 2 ** 64);

        borrowableAsset.setBalance(firstUser, firstAmount);
        vm.startPrank(firstUser);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(firstAmount), maxLLTV);
        vm.stopPrank();

        borrowableAsset.setBalance(secondUser, secondAmount);
        vm.startPrank(secondUser);
        borrowableAsset.approve(address(market), type(uint).max);
        market.modifyDeposit(int(secondAmount), maxLLTV);
        vm.stopPrank();

        assertEq(market.supplyShare(firstUser, maxLLTV), 1e18, "first user supply balance");
        assertEq(
            market.supplyShare(secondUser, maxLLTV), secondAmount * 1e18 / firstAmount, "second user supply balance"
        );
    }
}
