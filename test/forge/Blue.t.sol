// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SigUtils} from "./helpers/SigUtils.sol";

import "src/Blue.sol";
import {
    IBlueLiquidateCallback,
    IBlueRepayCallback,
    IBlueSupplyCallback,
    IBlueSupplyCollateralCallback
} from "src/interfaces/IBlueCallbacks.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract BlueTest is
    Test,
    IBlueSupplyCallback,
    IBlueSupplyCollateralCallback,
    IBlueRepayCallback,
    IBlueLiquidateCallback
{
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

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
        id = market.id();

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
        uint256 collateralAssetValue = collateralAsset.balanceOf(user).mulWadDown(collateralOracle.price());
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user).mulWadDown(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = blue.supplyShares(id, user);
        if (supplyShares == 0) return 0;

        uint256 totalShares = blue.totalSupplyShares(id);
        uint256 totalSupply = blue.totalSupply(id);
        return supplyShares.divWadDown(totalShares).mulWadDown(totalSupply);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShares(id, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = blue.totalBorrowShares(id);
        uint256 totalBorrow = blue.totalBorrow(id);
        return borrowerShares.divWadUp(totalShares).mulWadUp(totalBorrow);
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
        blue2.setOwner(newOwner);
        assertEq(blue2.owner(), newOwner, "owner");
    }

    function testTransferOwnershipWhenNotOwner(address attacker, address newOwner) public {
        vm.assume(attacker != OWNER);

        Blue blue2 = new Blue(OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue2.setOwner(newOwner);
    }

    function testEnableIrmWhenNotOwner(address attacker, IIrm newIrm) public {
        vm.assume(attacker != blue.owner());

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
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
        vm.expectRevert(bytes(Errors.IRM_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testEnableLltvWhenNotOwner(address attacker, uint256 newLltv) public {
        vm.assume(attacker != OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.enableLltv(newLltv);
    }

    function testEnableLltv(uint256 newLltv) public {
        newLltv = bound(newLltv, 0, FixedPointMathLib.WAD - 1);

        vm.prank(OWNER);
        blue.enableLltv(newLltv);

        assertTrue(blue.isLltvEnabled(newLltv));
    }

    function testEnableLltvShouldFailWhenLltvTooHigh(uint256 newLltv) public {
        newLltv = bound(newLltv, FixedPointMathLib.WAD, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_TOO_HIGH));
        blue.enableLltv(newLltv);
    }

    function testSetFee(uint256 fee) public {
        fee = bound(fee, 0, MAX_FEE);

        vm.prank(OWNER);
        blue.setFee(market, fee);

        assertEq(blue.fee(id), fee);
    }

    function testSetFeeShouldRevertIfTooHigh(uint256 fee) public {
        fee = bound(fee, MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.MAX_FEE_EXCEEDED));
        blue.setFee(market, fee);
    }

    function testSetFeeShouldRevertIfMarketNotCreated(Market memory marketFuzz, uint256 fee) public {
        vm.assume(neq(marketFuzz, market));
        fee = bound(fee, 0, FixedPointMathLib.WAD);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.setFee(marketFuzz, fee);
    }

    function testSetFeeShouldRevertIfNotOwner(uint256 fee, address caller) public {
        vm.assume(caller != OWNER);
        fee = bound(fee, 0, FixedPointMathLib.WAD);

        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.setFee(market, fee);
    }

    function testSetFeeRecipient(address recipient) public {
        vm.prank(OWNER);
        blue.setFeeRecipient(recipient);

        assertEq(blue.feeRecipient(), recipient);
    }

    function testSetFeeRecipientShouldRevertIfNotOwner(address caller, address recipient) public {
        vm.assume(caller != OWNER);

        vm.expectRevert(bytes(Errors.NOT_OWNER));
        vm.prank(caller);
        blue.setFeeRecipient(recipient);
    }

    function testFeeAccrues(uint256 amountLent, uint256 amountBorrowed, uint256 fee, uint256 timeElapsed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        timeElapsed = bound(timeElapsed, 1, 365 days);
        fee = bound(fee, 0, MAX_FEE);
        address recipient = OWNER;

        vm.startPrank(OWNER);
        blue.setFee(market, fee);
        blue.setFeeRecipient(recipient);
        vm.stopPrank();

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        uint256 totalSupplyBefore = blue.totalSupply(id);
        uint256 totalSupplySharesBefore = blue.totalSupplyShares(id);

        // Trigger an accrue.
        vm.warp(block.timestamp + timeElapsed);

        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");
        blue.withdrawCollateral(market, 1, address(this), address(this));

        uint256 totalSupplyAfter = blue.totalSupply(id);
        vm.assume(totalSupplyAfter > totalSupplyBefore);

        uint256 accrued = totalSupplyAfter - totalSupplyBefore;
        uint256 expectedFee = accrued.mulWadDown(fee);
        uint256 expectedFeeShares = expectedFee.mulDivDown(totalSupplySharesBefore, totalSupplyAfter - expectedFee);

        assertEq(blue.supplyShares(id, recipient), expectedFeeShares);
    }

    function testCreateMarketWithNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = irm;

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testSupplyOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, onBehalf, hex"");

        assertEq(blue.supplyShares(id, onBehalf), amount * SharesMath.VIRTUAL_SHARES, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testBorrow(uint256 amountLent, uint256 amountBorrowed, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this), hex"");

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            blue.borrow(market, amountBorrowed, BORROWER, receiver);
            return;
        }

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, receiver);

        assertEq(blue.borrowShares(id, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow share");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
    }

    function testWithdraw(uint256 amountLent, uint256 amountWithdrawn, uint256 amountBorrowed, address receiver)
        public
    {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            }
            blue.withdraw(market, amountWithdrawn, address(this), receiver);
            return;
        }

        blue.withdraw(market, amountWithdrawn, address(this), receiver);

        assertApproxEqAbs(
            blue.supplyShares(id, address(this)),
            (amountLent - amountWithdrawn) * SharesMath.VIRTUAL_SHARES,
            100,
            "supply share"
        );
        assertEq(borrowableAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
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

        blue.supply(market, amountBorrowed, address(this), hex"");

        vm.prank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        uint256 collateralValue = amountCollateral.mulWadDown(priceCollateral);
        uint256 borrowValue = amountBorrowed.mulWadUp(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.mulWadDown(LLTV))) {
            vm.prank(BORROWER);
            blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        } else {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
            blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        }
    }

    function testRepay(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(market, amountLent, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        blue.repay(market, amountRepaid, BORROWER, hex"");
        vm.stopPrank();

        assertApproxEqAbs(
            blue.borrowShares(id, BORROWER),
            (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES,
            100,
            "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed - amountRepaid, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testRepayOnBehalf(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid, address onBehalf)
        public
    {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        vm.assume(onBehalf != address(this));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent + amountRepaid);
        blue.supply(market, amountLent, address(this), hex"");

        vm.prank(onBehalf);
        blue.borrow(market, amountBorrowed, onBehalf, onBehalf);

        blue.repay(market, amountRepaid, onBehalf, hex"");

        assertApproxEqAbs(
            blue.borrowShares(id, onBehalf),
            (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES,
            100,
            "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(onBehalf), amountBorrowed, "onBehalf balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    function testSupplyCollateralOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(market, amount, onBehalf, hex"");

        assertEq(blue.collateral(id, onBehalf), amount, "collateral");
        assertEq(collateralAsset.balanceOf(onBehalf), 0, "onBehalf balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testWithdrawCollateral(uint256 amountDeposited, uint256 amountWithdrawn, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        blue.supplyCollateral(market, amountDeposited, address(this), hex"");

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(market, amountWithdrawn, address(this), receiver);
            return;
        }

        blue.withdrawCollateral(market, amountWithdrawn, address(this), receiver);

        assertEq(blue.collateral(id, address(this)), amountDeposited - amountWithdrawn, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountDeposited - amountWithdrawn, "blue balance");
    }

    function testLiquidate(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.mulWadDown(LLTV);
        uint256 amountBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = amountCollateral.mulWadDown(LLTV);
        uint256 incentive =
            FixedPointMathLib.WAD + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(LLTV) - FixedPointMathLib.WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(market, amountLent, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(market, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(blue.collateral(id, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.mulWadDown(LLTV);
        uint256 amountBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = amountCollateral;
        uint256 incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(market, amountLent, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(100e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(market, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
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
        blue.supply(market, firstAmount, address(this), hex"");

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        blue.supply(market, secondAmount, BORROWER, hex"");

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(
            blue.supplyShares(id, address(this)), firstAmount * SharesMath.VIRTUAL_SHARES, "expected shares first user"
        );
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertApproxEqAbs(
            blue.supplyShares(id, BORROWER),
            secondAmount * SharesMath.VIRTUAL_SHARES,
            100,
            "expected shares second user"
        );
    }

    function testUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.supply(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdraw(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.borrow(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.repay(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.supplyCollateral(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdrawCollateral(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.liquidate(marketFuzz, address(0), 1, hex"");
    }

    function testZeroAmount() public {
        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.supply(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.withdraw(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.borrow(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.repay(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.supplyCollateral(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.withdrawCollateral(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.liquidate(market, address(0), 0, hex"");
    }

    function testZeroAddress() public {
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.supply(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdraw(market, 1, address(this), address(0));

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.borrow(market, 1, address(this), address(0));

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.repay(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.supplyCollateral(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdrawCollateral(market, 1, address(this), address(0));
    }

    function testEmptyMarket(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max / SharesMath.VIRTUAL_SHARES);

        vm.expectRevert(stdError.arithmeticError);
        blue.withdraw(market, amount, address(this), address(this));

        vm.expectRevert(stdError.arithmeticError);
        blue.repay(market, amount, address(this), hex"");

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(market, amount, address(this), address(this));
    }

    function testSetAuthorization(address authorized, bool isAuthorized) public {
        blue.setAuthorization(authorized, isAuthorized);
        assertEq(blue.isAuthorized(address(this), authorized), isAuthorized);
    }

    function testNotAuthorized(address attacker) public {
        vm.assume(attacker != address(this));

        vm.startPrank(attacker);

        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdraw(market, 1, address(this), address(this));
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdrawCollateral(market, 1, address(this), address(this));
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.borrow(market, 1, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorization(address authorized) public {
        borrowableAsset.setBalance(address(this), 100 ether);
        collateralAsset.setBalance(address(this), 100 ether);

        blue.supply(market, 100 ether, address(this), hex"");
        blue.supplyCollateral(market, 100 ether, address(this), hex"");

        blue.setAuthorization(authorized, true);

        vm.startPrank(authorized);

        blue.withdraw(market, 1 ether, address(this), address(this));
        blue.withdrawCollateral(market, 1 ether, address(this), address(this));
        blue.borrow(market, 1 ether, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorizationWithSig(uint128 deadline, address authorized, uint256 privateKey, bool isAuthorized)
        public
    {
        vm.assume(deadline > block.timestamp);
        privateKey = bound(privateKey, 1, type(uint32).max); // "Private key must be less than the secp256k1 curve order (115792089237316195423570985008687907852837564279074904382605163141518161494337)."
        address authorizer = vm.addr(privateKey);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuthorized,
            nonce: blue.nonce(authorizer),
            deadline: block.timestamp + deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(blue.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );

        assertEq(blue.isAuthorized(authorizer, authorized), isAuthorized);
        assertEq(blue.nonce(authorizer), 1);
    }

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        blue.flashLoan(address(borrowableAsset), amount, bytes(""));

        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "balanceOf");
    }

    function testExtsLoad(uint256 slot, bytes32 value0) public {
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = bytes32(slot);
        slots[1] = bytes32(slot / 2);

        bytes32 value1 = keccak256(abi.encode(value0));
        vm.store(address(blue), slots[0], value0);
        vm.store(address(blue), slots[1], value1);

        bytes32[] memory values = blue.extsload(slots);

        assertEq(values.length, 2, "values.length");
        assertEq(values[0], slot > 0 ? value0 : value1, "value0");
        assertEq(values[1], value1, "value1");
    }

    function testSupplyCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(address(this), amount);
        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supply(market, amount, address(this), hex"");
        blue.supply(market, amount, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(address(this), amount);
        collateralAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supplyCollateral(market, amount, address(this), hex"");
        blue.supplyCollateral(
            market, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");
        blue.borrow(market, amount, address(this), address(this));

        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.repay(market, amount, address(this), hex"");
        blue.repay(market, amount, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);
        borrowableOracle.setPrice(1e18);
        borrowableAsset.setBalance(address(this), amount);
        collateralAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");
        blue.supplyCollateral(market, amount, address(this), hex"");
        blue.borrow(market, amount.mulWadDown(LLTV), address(this), address(this));

        borrowableOracle.setPrice(1.01e18);

        uint256 toSeize = amount.mulWadDown(LLTV);

        borrowableAsset.setBalance(address(this), toSeize);
        borrowableAsset.approve(address(blue), 0);
        vm.expectRevert();
        blue.liquidate(market, address(this), toSeize, hex"");
        blue.liquidate(market, address(this), toSeize, abi.encode(this.testLiquidateCallback.selector, hex""));
    }

    function testFlashActions(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);
        borrowableOracle.setPrice(1e18);
        uint256 toBorrow = amount.mulWadDown(LLTV);

        borrowableAsset.setBalance(address(this), 2 * toBorrow);
        blue.supply(market, toBorrow, address(this), hex"");

        blue.supplyCollateral(
            market, amount, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(blue.borrowShares(market.id(), address(this)), 0, "no borrow");

        blue.repay(market, toBorrow, address(this), abi.encode(this.testFlashActions.selector, abi.encode(amount)));
        assertEq(blue.collateral(market.id(), address(this)), 0, "no withdraw collateral");
    }

    // Callback functions.

    function onBlueSupply(uint256 amount, bytes memory data) external returns (bytes memory) {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            borrowableAsset.approve(address(blue), amount);
        }
        return hex"";
    }

    function onBlueSupplyCollateral(uint256 amount, bytes memory data) external returns (bytes memory) {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCollateralCallback.selector) {
            collateralAsset.approve(address(blue), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toBorrow = abi.decode(data, (uint256));
            collateralAsset.setBalance(address(this), amount);
            borrowableAsset.setBalance(address(this), toBorrow);
            blue.borrow(market, toBorrow, address(this), address(this));
        }
        return hex"";
    }

    function onBlueRepay(uint256 amount, bytes memory data) external returns (bytes memory) {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testRepayCallback.selector) {
            borrowableAsset.approve(address(blue), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toWithdraw = abi.decode(data, (uint256));
            blue.withdrawCollateral(market, toWithdraw, address(this), address(this));
        }
        return hex"";
    }

    function onBlueLiquidate(uint256, uint256 repaid, bytes memory data) external returns (bytes memory) {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            borrowableAsset.approve(address(blue), repaid);
        }
        return hex"";
    }

    function onBlueFlashLoan(address token, uint256 amount, bytes calldata) external {
        ERC20(token).approve(address(blue), amount);
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lltv != b.lltv
        || a.irm != b.irm;
}
