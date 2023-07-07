// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";

contract BlueTest is Test {
    using MathLib for uint;

    address private constant borrower = address(1234);
    address private constant liquidator = address(5678);
    uint private constant lLTV = 0.8 ether;

    Blue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    MarketParams public marketParams;
    Id public id;

    function setUp() public {
        // Create Blue.
        blue = new Blue(msg.sender);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();
        marketParams = MarketParams(
            IERC20(address(borrowableAsset)), IERC20(address(collateralAsset)), borrowableOracle, collateralOracle, lLTV
        );
        id = Id.wrap(keccak256(abi.encode(marketParams)));

        blue.createMarket(marketParams, 0);

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
        vm.startPrank(liquidator);
        borrowableAsset.approve(address(blue), type(uint).max);
        collateralAsset.approve(address(blue), type(uint).max);
        vm.stopPrank();
    }

    // To move to a test utils file later.

    function netWorth(address user) internal view returns (uint) {
        uint collateralAssetValue = collateralAsset.balanceOf(user).wMul(collateralOracle.price());
        uint borrowableAssetValue = borrowableAsset.balanceOf(user).wMul(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint) {
        uint supplyShares = blue.getPosition(id, user).supplyShare;
        if (supplyShares == 0) return 0;
        uint totalShares = blue.getMarket(id).totalSupplyShares;
        uint totalSupply = blue.getMarket(id).totalSupply;
        return supplyShares.wMul(totalSupply).wDiv(totalShares);
    }

    function borrowBalance(address user) internal view returns (uint) {
        uint borrowerShares = blue.getPosition(id, user).borrowShare;
        if (borrowerShares == 0) return 0;
        uint totalShares = blue.getMarket(id).totalBorrowShares;
        uint totalBorrow = blue.getMarket(id).totalBorrow;
        return borrowerShares.wMul(totalBorrow).wDiv(totalShares);
    }

    // Invariants

    function invariantLiquidity() public {
        assertLe(blue.getMarket(id).totalBorrow, blue.getMarket(id).totalSupply, "liquidity");
    }

    // Tests

    function testOwner(address owner) public {
        Blue blue2 = new Blue(owner);

        assertEq(blue2.owner(), owner, "owner");
    }

    function testTransferOwnership(address oldOwner, address newOwner) public {
        Blue blue2 = new Blue(oldOwner);

        vm.prank(oldOwner);
        blue2.transferOwnership(newOwner);
        assertEq(blue2.owner(), newOwner, "owner");
    }

    function testTransferOwnershipWhenNotOwner(address attacker, address newOwner) public {
        vm.assume(attacker != address(0xdead));

        Blue blue2 = new Blue(address(0xdead));

        vm.prank(attacker);
        vm.expectRevert("not owner");
        blue2.transferOwnership(newOwner);
    }

    function testSupply(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, amount);

        assertEq(blue.getPosition(id, address(this)).supplyShare, 1e18, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testBorrow(uint amountLent, uint amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent);

        if (amountBorrowed == 0) {
            blue.borrow(marketParams, amountBorrowed);
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(borrower);
            vm.expectRevert("not enough liquidity");
            blue.borrow(marketParams, amountBorrowed);
            return;
        }

        vm.prank(borrower);
        blue.borrow(marketParams, amountBorrowed);

        assertEq(blue.getPosition(id, borrower).borrowShare, 1e18, "borrow share");
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
    }

    function testWithdraw(uint amountLent, uint amountWithdrawn, uint amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent);

        vm.prank(borrower);
        blue.borrow(marketParams, amountBorrowed);

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert("not enough liquidity");
            }
            blue.withdraw(marketParams, amountWithdrawn);
            return;
        }

        blue.withdraw(marketParams, amountWithdrawn);

        assertApproxEqAbs(
            blue.getPosition(id, address(this)).supplyShare,
            (amountLent - amountWithdrawn) * 1e18 / amountLent,
            1e3,
            "supply share"
        );
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed - amountWithdrawn, "blue balance"
        );
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

        blue.supply(marketParams, amountBorrowed);

        vm.prank(borrower);
        blue.supplyCollateral(marketParams, amountCollateral);

        uint collateralValue = amountCollateral.wMul(priceCollateral);
        uint borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.wMul(lLTV))) {
            vm.prank(borrower);
            blue.borrow(marketParams, amountBorrowed);
        } else {
            vm.prank(borrower);
            vm.expectRevert("not enough collateral");
            blue.borrow(marketParams, amountBorrowed);
        }
    }

    function testRepay(uint amountLent, uint amountBorrowed, uint amountRepaid) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent);

        vm.startPrank(borrower);
        blue.borrow(marketParams, amountBorrowed);
        blue.repay(marketParams, amountRepaid);
        vm.stopPrank();

        assertApproxEqAbs(
            blue.getPosition(id, borrower).borrowShare,
            (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed,
            1e3,
            "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed - amountRepaid, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testSupplyCollateral(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(marketParams, amount);

        assertEq(blue.getPosition(id, address(this)).collateral, amount, "collateral");
        assertEq(collateralAsset.balanceOf(address(this)), 0, "this balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testWithdrawCollateral(uint amountDeposited, uint amountWithdrawn) public {
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        blue.supplyCollateral(marketParams, amountDeposited);

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(marketParams, amountWithdrawn);
            return;
        }

        blue.withdrawCollateral(marketParams, amountWithdrawn);

        assertEq(blue.getPosition(id, address(this)).collateral, amountDeposited - amountWithdrawn, "this collateral");
        assertEq(collateralAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountDeposited - amountWithdrawn, "blue balance");
    }

    function testLiquidate(uint amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint amountCollateral = amountLent;
        uint borrowingPower = amountCollateral.wMul(lLTV);
        uint amountBorrowed = borrowingPower.wMul(0.8e18);
        uint toSeize = amountCollateral.wMul(lLTV);
        uint incentive = WAD + ALPHA.wMul(WAD.wDiv(lLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(borrower, amountCollateral);
        borrowableAsset.setBalance(liquidator, amountBorrowed);

        // Supply
        blue.supply(marketParams, amountLent);

        // Borrow
        vm.startPrank(borrower);
        blue.supplyCollateral(marketParams, amountCollateral);
        blue.borrow(marketParams, amountBorrowed);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint liquidatorNetWorthBefore = netWorth(liquidator);

        // Liquidate
        vm.prank(liquidator);
        blue.liquidate(marketParams, borrower, toSeize);

        uint liquidatorNetWorthAfter = netWorth(liquidator);

        uint expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "liquidator net worth");
        assertApproxEqAbs(borrowBalance(borrower), amountBorrowed - expectedRepaid, 100, "borrower balance");
        assertEq(blue.getPosition(id, borrower).collateral, amountCollateral - toSeize, "borrower collateral");
    }

    function testRealizeBadDebt(uint amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint amountCollateral = amountLent;
        uint borrowingPower = amountCollateral.wMul(lLTV);
        uint amountBorrowed = borrowingPower.wMul(0.8e18);
        uint toSeize = amountCollateral;
        uint incentive = WAD + ALPHA.wMul(WAD.wDiv(marketParams.lLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(borrower, amountCollateral);
        borrowableAsset.setBalance(liquidator, amountBorrowed);

        // Supply
        blue.supply(marketParams, amountLent);

        // Borrow
        vm.startPrank(borrower);
        blue.supplyCollateral(marketParams, amountCollateral);
        blue.borrow(marketParams, amountBorrowed);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(100e18);

        uint liquidatorNetWorthBefore = netWorth(liquidator);

        // Liquidate
        vm.prank(liquidator);
        blue.liquidate(marketParams, borrower, toSeize);

        uint liquidatorNetWorthAfter = netWorth(liquidator);

        uint expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "liquidator net worth");
        assertEq(borrowBalance(borrower), 0, "borrower balance");
        assertEq(blue.getPosition(id, borrower).collateral, 0, "borrower collateral");
        uint expectedBadDebt = amountBorrowed - expectedRepaid;
        assertGt(expectedBadDebt, 0, "bad debt");
        assertApproxEqAbs(supplyBalance(address(this)), amountLent - expectedBadDebt, 10, "lender supply balance");
    }

    function testTwoUsersSupply(uint firstAmount, uint secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        blue.supply(marketParams, firstAmount);

        borrowableAsset.setBalance(borrower, secondAmount);
        vm.prank(borrower);
        blue.supply(marketParams, secondAmount);

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(blue.getPosition(id, address(this)).supplyShare, 1e18, "expected shares first user");
        assertApproxEqAbs(supplyBalance(borrower), secondAmount, 100, "same balance second user");
        assertEq(
            blue.getPosition(id, borrower).supplyShare, secondAmount * 1e18 / firstAmount, "expected shares second user"
        );
    }

    function testUnknownMarket(MarketParams memory marketFuzz) public {
        vm.assume(neq(marketFuzz, marketParams));

        vm.expectRevert("unknown market");
        blue.supply(marketFuzz, 1);

        vm.expectRevert("unknown market");
        blue.withdraw(marketFuzz, 1);

        vm.expectRevert("unknown market");
        blue.borrow(marketFuzz, 1);

        vm.expectRevert("unknown market");
        blue.repay(marketFuzz, 1);

        vm.expectRevert("unknown market");
        blue.supplyCollateral(marketFuzz, 1);

        vm.expectRevert("unknown market");
        blue.withdrawCollateral(marketFuzz, 1);

        vm.expectRevert("unknown market");
        blue.liquidate(marketFuzz, address(0), 1);
    }

    function testAmountZero() public {
        vm.expectRevert("zero amount");
        blue.supply(marketParams, 0);

        vm.expectRevert("zero amount");
        blue.withdraw(marketParams, 0);

        vm.expectRevert("zero amount");
        blue.borrow(marketParams, 0);

        vm.expectRevert("zero amount");
        blue.repay(marketParams, 0);

        vm.expectRevert("zero amount");
        blue.supplyCollateral(marketParams, 0);

        vm.expectRevert("zero amount");
        blue.withdrawCollateral(marketParams, 0);

        vm.expectRevert("zero amount");
        blue.liquidate(marketParams, address(0), 0);
    }

    function testEmptyMarket(uint amount) public {
        vm.assume(amount > 0);

        vm.expectRevert(stdError.divisionError);
        blue.withdraw(marketParams, amount);

        vm.expectRevert(stdError.divisionError);
        blue.repay(marketParams, amount);

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(marketParams, amount);
    }
}

function neq(MarketParams memory a, MarketParams memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lLTV != b.lLTV;
}
