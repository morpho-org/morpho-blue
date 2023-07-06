// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IRMMock as IRM} from "src/mocks/IRMMock.sol";

contract BlueTest is Test {
    using MathLib for uint;

    address private constant borrower = address(1234);
    address private constant liquidator = address(5678);
    uint private constant lLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);

    Blue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    IRM private irm;
    Market public market;
    Id public id;

    function setUp() public {
        // Create Blue.
        blue = new Blue(OWNER);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();

        irm = new IRM(blue);
        market = Market(
            IERC20(address(borrowableAsset)), IERC20(address(collateralAsset)), borrowableOracle, collateralOracle, irm, lLTV
        );
        id = Id.wrap(keccak256(abi.encode(market)));

        vm.startPrank(OWNER);
        blue.whitelistIRM(address(irm));
        blue.createMarket(market);
        vm.stopPrank();

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
        uint supplyShares = blue.supplyShare(id, user);
        if (supplyShares == 0) return 0;
        uint totalShares = blue.totalSupplyShares(id);
        uint totalSupply = blue.totalSupply(id);
        return supplyShares.wMul(totalSupply).wDiv(totalShares);
    }

    function borrowBalance(address user) internal view returns (uint) {
        uint borrowerShares = blue.borrowShare(id, user);
        if (borrowerShares == 0) return 0;
        uint totalShares = blue.totalBorrowShares(id);
        uint totalBorrow = blue.totalBorrow(id);
        return borrowerShares.wMul(totalBorrow).wDiv(totalShares);
    }

    // Invariants

    function invariantLiquidity() public {
        assertLe(blue.totalBorrow(id), blue.totalSupply(id), "liquidity");
    }

    // Tests

    function testOwner(address newOwner) public {
        Blue blue2 = new Blue(newOwner);

        assertEq(blue2.owner(), newOwner, "owner");
    }

    function testTransferOwnership(address oldOwner, address newOwner) public {
        Blue blue2 = new Blue(oldOwner);

        vm.prank(oldOwner);
        blue2.transferOwnership(newOwner);
        assertEq(blue2.owner(), newOwner, "owner");
    }

    function testTransferOwnershipWhenNotOwner(address attacker, address newOwner) public {
        vm.assume(attacker != OWNER);

        Blue blue2 = new Blue(OWNER);

        vm.prank(attacker);
        vm.expectRevert("not owner");
        blue2.transferOwnership(newOwner);
    }

    function testWhitelistIRMWhenNotOwner(address attacker) public {
        vm.assume(attacker != blue.owner());

        vm.prank(attacker);
        vm.expectRevert("not owner");
        blue.whitelistIRM(OWNER);
    }

    function testWhitelistIRM(address newIRM) public {
        vm.prank(OWNER);
        blue.whitelistIRM(newIRM);

        assertTrue(blue.isIRMWhitelisted(newIRM));
    }

    function testSupply(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount);

        assertEq(blue.supplyShare(id, address(this)), 1e18, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
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

        assertEq(blue.borrowShare(id, borrower), 1e18, "borrow share");
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
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

        assertApproxEqAbs(blue.supplyShare(id, address(this)), (amountLent - amountWithdrawn) * 1e18 / amountLent, 1e3, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed - amountWithdrawn, "blue balance");
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

        assertApproxEqAbs(blue.borrowShare(id, borrower), (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed, 1e3, "borrow share");
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed - amountRepaid, "borrower balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testSupplyCollateral(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount);

        assertEq(blue.collateral(id, address(this)), amount, "collateral");
        assertEq(collateralAsset.balanceOf(address(this)), 0, "this balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
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

        assertEq(blue.collateral(id, address(this)), amountDeposited - amountWithdrawn, "this collateral");
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
        uint incentive = WAD + alpha.wMul(WAD.wDiv(lLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(borrower, amountCollateral);
        borrowableAsset.setBalance(liquidator, amountBorrowed);

        // Supply
        blue.supply(market, amountLent);

        // Borrow
        vm.startPrank(borrower);
        blue.supplyCollateral(market, amountCollateral);
        blue.borrow(market, amountBorrowed);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint liquidatorNetWorthBefore = netWorth(liquidator);

        // Liquidate
        vm.prank(liquidator);
        blue.liquidate(market, borrower, toSeize);

        uint liquidatorNetWorthAfter = netWorth(liquidator);

        uint expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "liquidator net worth");
        assertApproxEqAbs(borrowBalance(borrower), amountBorrowed - expectedRepaid, 100, "borrower balance");
        assertEq(blue.collateral(id, borrower), amountCollateral - toSeize, "borrower collateral");
    }

    function testRealizeBadDebt(uint amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint amountCollateral = amountLent;
        uint borrowingPower = amountCollateral.wMul(lLTV);
        uint amountBorrowed = borrowingPower.wMul(0.8e18);
        uint toSeize = amountCollateral;
        uint incentive = WAD + alpha.wMul(WAD.wDiv(market.lLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(borrower, amountCollateral);
        borrowableAsset.setBalance(liquidator, amountBorrowed);

        // Supply
        blue.supply(market, amountLent);

        // Borrow
        vm.startPrank(borrower);
        blue.supplyCollateral(market, amountCollateral);
        blue.borrow(market, amountBorrowed);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(100e18);

        uint liquidatorNetWorthBefore = netWorth(liquidator);

        // Liquidate
        vm.prank(liquidator);
        blue.liquidate(market, borrower, toSeize);

        uint liquidatorNetWorthAfter = netWorth(liquidator);

        uint expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "liquidator net worth");
        assertEq(borrowBalance(borrower), 0, "borrower balance");
        assertEq(blue.collateral(id, borrower), 0, "borrower collateral");
        uint expectedBadDebt = amountBorrowed - expectedRepaid;
        assertGt(expectedBadDebt, 0, "bad debt");
        assertApproxEqAbs(supplyBalance(address(this)), amountLent - expectedBadDebt, 10, "lender supply balance");
    }

    function testTwoUsersSupply(uint firstAmount, uint secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        blue.supply(market, firstAmount);

        borrowableAsset.setBalance(borrower, secondAmount);
        vm.prank(borrower);
        blue.supply(market, secondAmount);

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(blue.supplyShare(id, address(this)), 1e18, "expected shares first user");
        assertApproxEqAbs(supplyBalance(borrower), secondAmount, 100, "same balance second user");
        assertEq(blue.supplyShare(id, borrower), secondAmount * 1e18 / firstAmount, "expected shares second user");
    }

    function testUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

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

        vm.expectRevert("zero amount");
        blue.liquidate(market, address(0), 0);
    }

    function testEmptyMarket(uint amount) public {
        vm.assume(amount > 0);

        vm.expectRevert(stdError.divisionError);
        blue.withdraw(market, amount);

        vm.expectRevert(stdError.divisionError);
        blue.repay(market, amount);

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(market, amount);
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lLTV != b.lLTV;
}
