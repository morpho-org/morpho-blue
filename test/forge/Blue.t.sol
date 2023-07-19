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

        irm = new Irm(blue);
        market = Market(
            IERC20(address(borrowableAsset)),
            IERC20(address(collateralAsset)),
            borrowableOracle,
            collateralOracle,
            irm,
            LLTV
        );
        id = Id.wrap(keccak256(abi.encode(market)));

        vm.startPrank(OWNER);
        blue.enableIrm(irm);
        blue.enableLltv(LLTV);
        blue.createMarket(market);
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
        uint256 supplyShares = blue.supplyShare(id, user);
        if (supplyShares == 0) return 0;
        uint256 totalShares = blue.totalSupplyShares(id);
        uint256 totalSupply = blue.totalSupply(id);
        return supplyShares.wMul(totalSupply).wDiv(totalShares);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShare(id, user);
        if (borrowerShares == 0) return 0;
        uint256 totalShares = blue.totalBorrowShares(id);
        uint256 totalBorrow = blue.totalBorrow(id);
        return borrowerShares.wMul(totalBorrow).wDiv(totalShares);
    }

    // Invariants

    function invariantLiquidity() public {
        assertLe(blue.totalBorrow(id), blue.totalSupply(id), "liquidity");
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

    function testCreateMarketWithEnabledIrm(Market memory marketFuzz) public {
        marketFuzz.lltv = LLTV;

        vm.startPrank(OWNER);
        blue.enableIrm(marketFuzz.irm);
        blue.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithNotEnabledIrm(Market memory marketFuzz) public {
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

    function testSetFee(uint256 fee) public {
        fee = bound(fee, 0, WAD);

        vm.prank(OWNER);
        blue.setFee(market, fee);

        assertEq(blue.fee(id), fee);
    }

    function testSetFeeShouldRevertIfTooHigh(uint256 fee) public {
        fee = bound(fee, WAD + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert("fee must be <= 1");
        blue.setFee(market, fee);
    }

    function testSetFeeShouldRevertIfMarketNotCreated(Market memory marketFuzz, uint256 fee) public {
        vm.assume(neq(marketFuzz, market));
        fee = bound(fee, 0, WAD);

        vm.prank(OWNER);
        vm.expectRevert("unknown market");
        blue.setFee(marketFuzz, fee);
    }

    function testSetFeeShouldRevertIfNotOwner(uint256 fee, address caller) public {
        vm.assume(caller != OWNER);
        fee = bound(fee, 0, WAD);

        vm.expectRevert("not owner");
        blue.setFee(market, fee);
    }

    function testSetFeeRecipient(address recipient) public {
        vm.prank(OWNER);
        blue.setFeeRecipient(recipient);

        assertEq(blue.feeRecipient(), recipient);
    }

    function testSetFeeRecipientShouldRevertIfNotOwner(address caller, address recipient) public {
        vm.assume(caller != OWNER);

        vm.expectRevert("not owner");
        vm.prank(caller);
        blue.setFeeRecipient(recipient);
    }

    function testFeeAccrues(uint256 amountLent, uint256 amountBorrowed, uint256 fee, uint256 timeElapsed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        timeElapsed = bound(timeElapsed, 1, 365 days);
        fee = bound(fee, 0, 1e18);
        address recipient = OWNER;

        vm.startPrank(OWNER);
        blue.setFee(market, fee);
        blue.setFeeRecipient(recipient);
        vm.stopPrank();

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this));

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);

        uint256 totalSupplyBefore = blue.totalSupply(id);
        uint256 totalSupplySharesBefore = blue.totalSupplyShares(id);

        // Trigger an accrue.
        vm.warp(block.timestamp + timeElapsed);
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this));
        blue.withdrawCollateral(market, 1, address(this));
        uint256 totalSupplyAfter = blue.totalSupply(id);

        vm.assume(totalSupplyAfter > totalSupplyBefore);

        uint256 accrued = totalSupplyAfter - totalSupplyBefore;
        uint256 expectedFee = accrued.wMul(fee);
        uint256 expectedFeeShares = expectedFee.wMul(totalSupplySharesBefore).wDiv(blue.totalSupply(id) - expectedFee);

        assertEq(blue.supplyShare(id, recipient), expectedFeeShares);
    }

    function testCreateMarketWithNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = irm;

        vm.prank(OWNER);
        vm.expectRevert("LLTV not enabled");
        blue.createMarket(marketFuzz);
    }

    function testSupplyOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, onBehalf);

        assertEq(blue.supplyShare(id, onBehalf), 1e18, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testBorrow(uint256 amountLent, uint256 amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this));

        if (amountBorrowed == 0) {
            blue.borrow(market, amountBorrowed, address(this));
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert("not enough liquidity");
            blue.borrow(market, amountBorrowed, BORROWER);
            return;
        }

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);

        assertEq(blue.borrowShare(id, BORROWER), 1e18, "borrow share");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
    }

    function testWithdraw(uint256 amountLent, uint256 amountWithdrawn, uint256 amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this));

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert("not enough liquidity");
            }
            blue.withdraw(market, amountWithdrawn, address(this));
            return;
        }

        blue.withdraw(market, amountWithdrawn, address(this));

        assertApproxEqAbs(
            blue.supplyShare(id, address(this)), (amountLent - amountWithdrawn) * 1e18 / amountLent, 1e3, "supply share"
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

        blue.supply(market, amountBorrowed, address(this));

        vm.prank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER);

        uint256 collateralValue = amountCollateral.wMul(priceCollateral);
        uint256 borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.wMul(LLTV))) {
            vm.prank(BORROWER);
            blue.borrow(market, amountBorrowed, BORROWER);
        } else {
            vm.prank(BORROWER);
            vm.expectRevert("not enough collateral");
            blue.borrow(market, amountBorrowed, BORROWER);
        }
    }

    function testRepay(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this));

        vm.startPrank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);
        blue.repay(market, amountRepaid, BORROWER);
        vm.stopPrank();

        assertApproxEqAbs(
            blue.borrowShare(id, BORROWER), (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed, 1e3, "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed - amountRepaid, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testRepayOnBehalf(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid, address onBehalf)
        public
    {
        vm.assume(onBehalf != address(blue));
        vm.assume(onBehalf != address(this));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent + amountRepaid);
        blue.supply(market, amountLent, address(this));

        vm.prank(onBehalf);
        blue.borrow(market, amountBorrowed, onBehalf);

        blue.repay(market, amountRepaid, onBehalf);

        assertApproxEqAbs(
            blue.borrowShare(id, onBehalf), (amountBorrowed - amountRepaid) * 1e18 / amountBorrowed, 1e3, "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(onBehalf), amountBorrowed, "onBehalf balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testSupplyCollateralOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, onBehalf);

        assertEq(blue.collateral(id, onBehalf), amount, "collateral");
        assertEq(collateralAsset.balanceOf(onBehalf), 0, "onBehalf balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testWithdrawCollateral(uint256 amountDeposited, uint256 amountWithdrawn) public {
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        blue.supplyCollateral(market, amountDeposited, address(this));

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(market, amountWithdrawn, address(this));
            return;
        }

        blue.withdrawCollateral(market, amountWithdrawn, address(this));

        assertEq(blue.collateral(id, address(this)), amountDeposited - amountWithdrawn, "this collateral");
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
        blue.supply(market, amountLent, address(this));

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(market, BORROWER, toSeize);

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(blue.collateral(id, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.wMul(LLTV);
        uint256 amountBorrowed = borrowingPower.wMul(0.8e18);
        uint256 toSeize = amountCollateral;
        uint256 incentive = WAD + ALPHA.wMul(WAD.wDiv(market.lltv) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(market, amountLent, address(this));

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(100e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(market, BORROWER, toSeize);

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid = toSeize.wMul(collateralOracle.price()).wDiv(incentive).wDiv(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.wMul(collateralOracle.price())
            - expectedRepaid.wMul(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertEq(borrowBalance(BORROWER), 0, "BORROWER balance");
        assertEq(blue.collateral(id, BORROWER), 0, "BORROWER collateral");
        uint256 expectedBadDebt = amountBorrowed - expectedRepaid;
        assertGt(expectedBadDebt, 0, "bad debt");
        assertApproxEqAbs(supplyBalance(address(this)), amountLent - expectedBadDebt, 10, "lender supply balance");
        assertApproxEqAbs(blue.totalBorrow(id), 0, 10, "total borrow");
    }

    function testTwoUsersSupply(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        blue.supply(market, firstAmount, address(this));

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        blue.supply(market, secondAmount, BORROWER);

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(blue.supplyShare(id, address(this)), 1e18, "expected shares first user");
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertEq(blue.supplyShare(id, BORROWER), secondAmount * 1e18 / firstAmount, "expected shares second user");
    }

    function testUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert("unknown market");
        blue.supply(marketFuzz, 1, address(this));

        vm.expectRevert("unknown market");
        blue.withdraw(marketFuzz, 1, address(this));

        vm.expectRevert("unknown market");
        blue.borrow(marketFuzz, 1, address(this));

        vm.expectRevert("unknown market");
        blue.repay(marketFuzz, 1, address(this));

        vm.expectRevert("unknown market");
        blue.supplyCollateral(marketFuzz, 1, address(this));

        vm.expectRevert("unknown market");
        blue.withdrawCollateral(marketFuzz, 1, address(this));

        vm.expectRevert("unknown market");
        blue.liquidate(marketFuzz, address(0), 1);
    }

    function testAmountZero() public {
        vm.expectRevert("zero amount");
        blue.supply(market, 0, address(this));

        vm.expectRevert("zero amount");
        blue.withdraw(market, 0, address(this));

        vm.expectRevert("zero amount");
        blue.borrow(market, 0, address(this));

        vm.expectRevert("zero amount");
        blue.repay(market, 0, address(this));

        vm.expectRevert("zero amount");
        blue.supplyCollateral(market, 0, address(this));

        vm.expectRevert("zero amount");
        blue.withdrawCollateral(market, 0, address(this));

        vm.expectRevert("zero amount");
        blue.liquidate(market, address(0), 0);
    }

    function testEmptyMarket(uint256 amount) public {
        vm.assume(amount > 0);

        vm.expectRevert(stdError.divisionError);
        blue.withdraw(market, amount, address(this));

        vm.expectRevert(stdError.divisionError);
        blue.repay(market, amount, address(this));

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(market, amount, address(this));
    }

    function testSetApproval(address manager, bool isAllowed) public {
        blue.setApproval(manager, isAllowed);
        assertEq(blue.isApproved(address(this), manager), isAllowed);
    }

    function testNotApproved(address attacker) public {
        vm.assume(attacker != address(this));

        vm.startPrank(attacker);

        vm.expectRevert("not approved");
        blue.withdraw(market, 1, address(this));
        vm.expectRevert("not approved");
        blue.withdrawCollateral(market, 1, address(this));
        vm.expectRevert("not approved");
        blue.borrow(market, 1, address(this));

        vm.stopPrank();
    }

    function testApproved(address manager) public {
        borrowableAsset.setBalance(address(this), 100 ether);
        collateralAsset.setBalance(address(this), 100 ether);

        blue.supply(market, 100 ether, address(this));
        blue.supplyCollateral(market, 100 ether, address(this));

        blue.setApproval(manager, true);

        vm.startPrank(manager);

        blue.withdraw(market, 1 ether, address(this));
        blue.withdrawCollateral(market, 1 ether, address(this));
        blue.borrow(market, 1 ether, address(this));

        vm.stopPrank();
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lltv != b.lltv
        || a.irm != b.irm;
}
