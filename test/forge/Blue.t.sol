// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract BlueTest is Test {
    using MathLib for uint256;

    address private constant BORROWER = address(1234);
    address private constant LIQUIDATOR = address(5678);
    uint256 private constant LLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);

    Blue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    Irm private irm;
    MarketParams public marketParams;
    Id public id;

    function setUp() public {
        // Create Blue.
        blue = new Blue(OWNER);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();
        irm = new Irm(blue);
        marketParams = MarketParams(
            IERC20(address(borrowableAsset)),
            IERC20(address(collateralAsset)),
            borrowableOracle,
            collateralOracle,
            irm,
            LLTV
        );
        id = Id.wrap(keccak256(abi.encode(marketParams)));

        vm.startPrank(OWNER);
        blue.enableIrm(irm);
        blue.enableLltv(LLTV);
        blue.createMarket(marketParams);
        vm.stopPrank();

        // We set the price of the borrowable asset to zero so that borrowers
        // don't need to deposit any collateral.
        borrowableOracle.setPrice(0);
        collateralOracle.setPrice(1e18);

        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.startPrank(BORROWER);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(LIQUIDATOR);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.stopPrank();
    }

    // To move to a test utils file later.

    function netWorth(address user) internal view returns (uint256) {
        uint256 collateralAssetValue = collateralAsset.balanceOf(user).wMul(collateralOracle.price());
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user).wMul(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = blue.getPosition(id, user).supplyShare;
        if (supplyShares == 0) return 0;
        uint256 totalShares = blue.getMarket(id).totalSupplyShares;
        uint256 totalSupply = blue.getMarket(id).totalSupply;
        return supplyShares.wMul(totalSupply).wDiv(totalShares);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.getPosition(id, user).borrowShare;
        if (borrowerShares == 0) return 0;
        uint256 totalShares = blue.getMarket(id).totalBorrowShares;
        uint256 totalBorrow = blue.getMarket(id).totalBorrow;
        return borrowerShares.wMul(totalBorrow).wDiv(totalShares);
    }

    // Invariants

    function invariantLiquidity() public {
        assertLe(blue.getMarket(id).totalBorrow, blue.getMarket(id).totalSupply, "liquidity");
    }

    function invariantLltvEnabled() public {
        assertTrue(blue.isLltvEnabled(LLTV));
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

    function testEnableIrmWhenNotOwner(address attacker, IIrm newIrm) public {
        vm.assume(attacker != blue.owner());

        vm.prank(attacker);
        vm.expectRevert("not owner");
        blue.enableIrm(newIrm);
    }

    function testEnableIrm(IIrm newIrm) public {
        vm.prank(OWNER);
        blue.enableIrm(newIrm);

        assertTrue(blue.isIrmEnabled(newIrm));
    }

    function testCreateMarketWithEnabledIrm(MarketParams memory marketFuzz) public {
        marketFuzz.lltv = LLTV;

        vm.startPrank(OWNER);
        blue.enableIrm(marketFuzz.irm);
        blue.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithNotEnabledIrm(MarketParams memory marketFuzz) public {
        vm.assume(marketFuzz.irm != irm);

        vm.prank(OWNER);
        vm.expectRevert("IRM not enabled");
        blue.createMarket(marketFuzz);
    }

    function testEnableLltvWhenNotOwner(address attacker, uint256 newLltv) public {
        vm.assume(attacker != OWNER);

        vm.prank(attacker);
        vm.expectRevert("not owner");
        blue.enableLltv(newLltv);
    }

    function testEnableLltv(uint256 newLltv) public {
        newLltv = bound(newLltv, 0, WAD - 1);

        vm.prank(OWNER);
        blue.enableLltv(newLltv);

        assertTrue(blue.isLltvEnabled(newLltv));
    }

    function testEnableLltvShouldFailWhenLltvTooHigh(uint256 newLltv) public {
        newLltv = bound(newLltv, WAD, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert("LLTV too high");
        blue.enableLltv(newLltv);
    }

    function testCreateMarketWithNotEnabledLltv(MarketParams memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = irm;

        vm.prank(OWNER);
        vm.expectRevert("LLTV not enabled");
        blue.createMarket(marketFuzz);
    }

    function testSupply(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, amount);

        assertEq(blue.getPosition(id, address(this)).supplyShare, 1e18, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testBorrow(uint256 amountLent, uint256 amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent);

        if (amountBorrowed == 0) {
            blue.borrow(marketParams, amountBorrowed);
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert("not enough liquidity");
            blue.borrow(marketParams, amountBorrowed);
            return;
        }

        vm.prank(BORROWER);
        blue.borrow(marketParams, amountBorrowed);

        assertEq(blue.getPosition(id, BORROWER).borrowShare, 1e18, "borrow share");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
    }

    function testWithdraw(uint256 amountLent, uint256 amountWithdrawn, uint256 amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent);

        vm.prank(BORROWER);
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
        uint256 amountCollateral,
        uint256 amountBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(marketParams, amountBorrowed);

        vm.prank(BORROWER);
        blue.supplyCollateral(marketParams, amountCollateral);

        uint256 collateralValue = amountCollateral.wMul(priceCollateral);
        uint256 borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.wMul(LLTV))) {
            vm.prank(BORROWER);
            blue.borrow(marketParams, amountBorrowed);
        } else {
            vm.prank(BORROWER);
            vm.expectRevert("not enough collateral");
            blue.borrow(marketParams, amountBorrowed);
        }
    }

    function testRepay(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent);

        vm.startPrank(BORROWER);
        blue.borrow(marketParams, amountBorrowed);
        blue.repay(marketParams, amountRepaid);
        vm.stopPrank();

        assertApproxEqAbs(
            blue.getPosition(id, BORROWER).borrowShare,
            (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed,
            1e3,
            "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed - amountRepaid, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testSupplyCollateral(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(marketParams, amount);

        assertEq(blue.getPosition(id, address(this)).collateral, amount, "collateral");
        assertEq(collateralAsset.balanceOf(address(this)), 0, "this balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testWithdrawCollateral(uint256 amountDeposited, uint256 amountWithdrawn) public {
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

    function testLiquidate(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.wMul(LLTV);
        uint256 amountBorrowed = borrowingPower.wMul(0.8e18);
        uint256 toSeize = amountCollateral.wMul(LLTV);
        uint256 incentive = WAD + ALPHA.wMul(WAD.wDiv(LLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(marketParams, amountLent);

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(marketParams, amountCollateral);
        blue.borrow(marketParams, amountBorrowed);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(marketParams, BORROWER, toSeize);

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(blue.getPosition(id, BORROWER).collateral, amountCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.wMul(LLTV);
        uint256 amountBorrowed = borrowingPower.wMul(0.8e18);
        uint256 toSeize = amountCollateral;
        uint256 incentive = WAD + ALPHA.wMul(WAD.wDiv(marketParams.lltv) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(marketParams, amountLent);

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(marketParams, amountCollateral);
        blue.borrow(marketParams, amountBorrowed);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(100e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(marketParams, BORROWER, toSeize);

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertEq(borrowBalance(BORROWER), 0, "BORROWER balance");
        assertEq(blue.getPosition(id, BORROWER).collateral, 0, "BORROWER collateral");
        uint256 expectedBadDebt = amountBorrowed - expectedRepaid;
        assertGt(expectedBadDebt, 0, "bad debt");
        assertApproxEqAbs(supplyBalance(address(this)), amountLent - expectedBadDebt, 10, "lender supply balance");
    }

    function testTwoUsersSupply(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        blue.supply(marketParams, firstAmount);

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        blue.supply(marketParams, secondAmount);

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(blue.getPosition(id, address(this)).supplyShare, 1e18, "expected shares first user");
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertEq(
            blue.getPosition(id, BORROWER).supplyShare, secondAmount * 1e18 / firstAmount, "expected shares second user"
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

    function testEmptyMarket(uint256 amount) public {
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
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lltv != b.lltv
        || a.irm != b.irm;
}
