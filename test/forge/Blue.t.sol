// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SigUtils} from "./helpers/SigUtils.sol";

import "src/Blue.sol";
import {SharesMathLib} from "src/libraries/SharesMathLib.sol";
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
    using MarketLib for MarketParams;
    using SharesMathLib for uint256;
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    address private constant BORROWER = address(0x1234);
    address private constant LIQUIDATOR = address(0x5678);
    uint256 private constant LLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);

    IBlue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private oracle;
    Irm private irm;
    MarketParams private marketParams;
    Id private id;

    function setUp() public {
        // Create Blue.
        blue = new Blue(OWNER);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        oracle = new Oracle();

        irm = new Irm(blue);

        marketParams = MarketParams(address(borrowableAsset), address(collateralAsset), address(oracle), address(irm), LLTV);
        id = marketParams.id();

        vm.startPrank(OWNER);
        blue.enableIrm(address(irm));
        blue.enableLltv(LLTV);
        blue.createMarket(marketParams);
        vm.stopPrank();

        oracle.setPrice(WAD);

        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);

        vm.startPrank(BORROWER);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        blue.setAuthorization(address(this), true);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Calculates the net worth of the given user quoted in borrowable asset.
    // TODO: To move to a test utils file later.
    function netWorth(address user) internal view returns (uint256) {
        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        uint256 collateralAssetValue = collateralAsset.balanceOf(user).mulDivDown(collateralPrice, priceScale);
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user);

        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = blue.supplyShares(id, user);
        if (supplyShares == 0) return 0;

        uint256 totalShares = blue.totalSupplyShares(id);
        uint256 totalSupply = blue.totalSupply(id);
        return supplyShares.wDivDown(totalShares).wMulDown(totalSupply);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShares(id, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = blue.totalBorrowShares(id);
        uint256 totalBorrow = blue.totalBorrow(id);
        return borrowerShares.wDivUp(totalShares).wMulUp(totalBorrow);
    }

    // Invariants

    function invariantLiquidity() public {
        assertLe(blue.totalBorrow(id), blue.totalSupply(id), "liquidity");
    }

    function invariantLltvEnabled() public {
        assertTrue(blue.isLltvEnabled(LLTV));
    }

    function invariantIrmEnabled() public {
        assertTrue(blue.isIrmEnabled(address(irm)));
    }

    function invariantMarketCreated() public {
        assertGt(blue.lastUpdate(id), 0);
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
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        blue2.setOwner(newOwner);
    }

    function testEnableIrmWhenNotOwner(address attacker, address newIrm) public {
        vm.assume(attacker != blue.owner());

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        blue.enableIrm(newIrm);
    }

    function testEnableIrm(address newIrm) public {
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
        vm.assume(marketFuzz.irm != address(irm));

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testEnableLltvWhenNotOwner(address attacker, uint256 newLltv) public {
        vm.assume(attacker != OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
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
        vm.expectRevert(bytes(ErrorsLib.LLTV_TOO_HIGH));
        blue.enableLltv(newLltv);
    }

    function testSetFee(uint256 fee) public {
        fee = bound(fee, 0, MAX_FEE);

        vm.prank(OWNER);
        blue.setFee(marketParams, fee);

        assertEq(blue.fee(id), fee);
    }

    function testSetFeeShouldRevertIfTooHigh(uint256 fee) public {
        fee = bound(fee, MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MAX_FEE_EXCEEDED));
        blue.setFee(marketParams, fee);
    }

    function testSetFeeShouldRevertIfMarketNotCreated(MarketParams memory marketFuzz, uint256 fee) public {
        vm.assume(neq(marketFuzz, marketParams));
        fee = bound(fee, 0, WAD);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.setFee(marketFuzz, fee);
    }

    function testSetFeeShouldRevertIfNotOwner(uint256 fee, address caller) public {
        vm.assume(caller != OWNER);
        fee = bound(fee, 0, WAD);

        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        blue.setFee(marketParams, fee);
    }

    function testSetFeeRecipient(address recipient) public {
        vm.prank(OWNER);
        blue.setFeeRecipient(recipient);

        assertEq(blue.feeRecipient(), recipient);
    }

    function testSetFeeRecipientShouldRevertIfNotOwner(address caller, address recipient) public {
        vm.assume(caller != OWNER);

        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
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
        blue.setFee(marketParams, fee);
        blue.setFeeRecipient(recipient);
        vm.stopPrank();

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent, 0, address(this), hex"");

        uint256 collateralAmount = amountBorrowed.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        blue.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

        vm.prank(BORROWER);
        blue.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);

        uint256 totalSupplyBefore = blue.totalSupply(id);
        uint256 totalSupplySharesBefore = blue.totalSupplyShares(id);

        // Trigger an accrue.
        vm.warp(block.timestamp + timeElapsed);

        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(marketParams, 1, address(this), hex"");
        blue.withdrawCollateral(marketParams, 1, address(this), address(this));

        uint256 totalSupplyAfter = blue.totalSupply(id);
        vm.assume(totalSupplyAfter > totalSupplyBefore);

        uint256 accrued = totalSupplyAfter - totalSupplyBefore;
        uint256 expectedFee = accrued * fee / 100;
        uint256 expectedFeeShares = expectedFee.mulDivDown(totalSupplySharesBefore, totalSupplyAfter - expectedFee);

        assertEq(blue.supplyShares(id, recipient), expectedFeeShares);
    }

    function testCreateMarketWithNotEnabledLltv(MarketParams memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = address(irm);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testSupplyAmount(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);
        uint256 shares = amount.toSharesDown(blue.totalSupply(id), blue.totalSupplyShares(id));

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, amount, 0, onBehalf, hex"");

        assertEq(blue.supplyShares(id, onBehalf), shares, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testSupplyShares(uint256 shares, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        shares = bound(shares, 1, 2 ** 64);
        uint256 amount = shares.toAssetsUp(blue.totalSupply(id), blue.totalSupplyShares(id));

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, 0, shares, onBehalf, hex"");

        assertEq(blue.supplyShares(id, onBehalf), shares, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testBorrowAmount(uint256 amountLent, uint256 amountBorrowed, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        uint256 shares = amountBorrowed.toSharesUp(blue.totalBorrow(id), blue.totalBorrowShares(id));

        borrowableAsset.setBalance(address(this), amountLent);
        blue.supply(marketParams, amountLent, 0, address(this), hex"");

        uint256 collateralAmount = shares.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id)).wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        blue.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
            blue.borrow(marketParams, amountBorrowed, 0, BORROWER, receiver);
            return;
        }

        vm.prank(BORROWER);
        blue.borrow(marketParams, amountBorrowed, 0, BORROWER, receiver);

        assertEq(blue.borrowShares(id, BORROWER), amountBorrowed * SharesMathLib.VIRTUAL_SHARES, "borrow share");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
    }

    function testBorrowShares(uint256 shares) public {
        shares = bound(shares, 1, 2 ** 64);
        uint256 amount = shares.toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id));

        borrowableAsset.setBalance(address(this), amount);
        if (amount > 0) blue.supply(marketParams, amount, 0, address(this), hex"");

        uint256 collateralAmount = shares.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id)).wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        if (collateralAmount > 0) blue.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

        vm.prank(BORROWER);
        blue.borrow(marketParams, 0, shares, BORROWER, BORROWER);

        assertEq(blue.borrowShares(id, BORROWER), shares, "borrow share");
        assertEq(borrowableAsset.balanceOf(BORROWER), amount, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), 0, "blue balance");
    }

    // function _testWithdrawCommon(uint256 amountLent) public {
    //     amountLent = bound(amountLent, 1, 2 ** 64);

    //     borrowableAsset.setBalance(address(this), amountLent);
    //     blue.supply(marketParams, amountLent, 0, address(this), hex"");

    //     // Accrue interests.
    //     stdstore.target(address(blue)).sig("totalSupply(bytes32)").with_key(Id.unwrap(id)).checked_write(
    //         blue.totalSupply(id) * 4 / 3
    //     );
    //     borrowableAsset.setBalance(address(blue), blue.totalSupply(id));
    // }

    // function testWithdrawShares(uint256 amountLent, uint256 sharesWithdrawn, uint256 amountBorrowed, address receiver)
    //     public
    // {
    //     vm.assume(receiver != BORROWER);
    //     vm.assume(receiver != address(0));
    //     vm.assume(receiver != address(blue));
    //     vm.assume(receiver != address(this));
    //     sharesWithdrawn = bound(sharesWithdrawn, 1, 2 ** 64);

    //     _testWithdrawCommon(amountLent);
    //     amountBorrowed = bound(amountBorrowed, 1, blue.totalSupply(id));

    //     uint256 collateralAmount = amountBorrowed.wDivUp(LLTV);
    //     collateralAsset.setBalance(address(this), collateralAmount);
    //     blue.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

    //     blue.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);

    //     uint256 totalSupplyBefore = blue.totalSupply(id);
    //     uint256 supplySharesBefore = blue.supplyShares(id, address(this));
    //     uint256 amountWithdrawn = sharesWithdrawn.toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));

    //     if (sharesWithdrawn > blue.supplyShares(id, address(this))) {
    //         vm.expectRevert(stdError.arithmeticError);
    //         blue.withdraw(marketParams, 0, sharesWithdrawn, address(this), receiver);
    //         return;
    //     } else if (amountWithdrawn > totalSupplyBefore - amountBorrowed) {
    //         vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
    //         blue.withdraw(marketParams, 0, sharesWithdrawn, address(this), receiver);
    //         return;
    //     }

    //     blue.withdraw(marketParams, 0, sharesWithdrawn, address(this), receiver);

    //     assertEq(blue.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
    //     assertEq(borrowableAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
    //     assertEq(
    //         borrowableAsset.balanceOf(address(blue)),
    //         totalSupplyBefore - amountBorrowed - amountWithdrawn,
    //         "blue balance"
    //     );
    // }

    // function testWithdrawAmount(uint256 amountLent, uint256 exactAmountWithdrawn) public {
    //     _testWithdrawCommon(amountLent);

    //     uint256 totalSupplyBefore = blue.totalSupply(id);
    //     uint256 supplySharesBefore = blue.supplyShares(id, address(this));
    //     exactAmountWithdrawn = bound(
    //         exactAmountWithdrawn, 1, supplySharesBefore.toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id))
    //     );
    //     blue.withdraw(marketParams, exactAmountWithdrawn, 0, address(this), address(this));

    //     // assertEq(blue.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
    //     assertEq(borrowableAsset.balanceOf(address(this)), exactAmountWithdrawn, "this balance");
    //     assertEq(borrowableAsset.balanceOf(address(blue)), totalSupplyBefore - exactAmountWithdrawn, "blue balance");
    // }

    // function testWithdrawAll(uint256 amountLent) public {
    //     _testWithdrawCommon(amountLent);

    //     uint256 totalSupplyBefore = blue.totalSupply(id);
    //     uint256 amountWithdrawn =
    //         blue.supplyShares(id, address(this)).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
    //     blue.withdraw(marketParams, 0, blue.supplyShares(id, address(this)), address(this), address(this));

    //     assertEq(blue.supplyShares(id, address(this)), 0, "supply share");
    //     assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
    //     assertEq(borrowableAsset.balanceOf(address(blue)), totalSupplyBefore - amountWithdrawn, "blue balance");
    // }

    // function _testRepayCommon(uint256 amountBorrowed, address borrower) public {
    //     amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

    //     borrowableAsset.setBalance(address(this), 2 ** 66);
    //     blue.supply(marketParams, amountBorrowed, 0, address(this), hex"");

    //     uint256 collateralAmount = amountBorrowed.wDivUp(LLTV);
    //     collateralAsset.setBalance(address(this), collateralAmount);
    //     blue.supplyCollateral(marketParams, collateralAmount, borrower, hex"");

    //     vm.prank(borrower);
    //     blue.borrow(marketParams, amountBorrowed, 0, borrower, borrower);

    //     // Accrue interests.
    //     stdstore.target(address(blue)).sig("totalBorrow(bytes32)").with_key(Id.unwrap(id)).checked_write(
    //         blue.totalBorrow(id) * 4 / 3
    //     );
    // }

    // function testRepayShares(uint256 amountBorrowed, uint256 sharesRepaid, address onBehalf) public {
    //     vm.assume(onBehalf != address(0));
    //     vm.assume(onBehalf != address(blue));
    //     _testRepayCommon(amountBorrowed, onBehalf);

    //     uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
    //     uint256 borrowSharesBefore = blue.borrowShares(id, onBehalf);
    //     sharesRepaid = bound(sharesRepaid, 1, borrowSharesBefore);

    //     uint256 amountRepaid = sharesRepaid.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
    //     blue.repay(marketParams, 0, sharesRepaid, onBehalf, hex"");

    //     assertEq(blue.borrowShares(id, onBehalf), borrowSharesBefore - sharesRepaid, "borrow share");
    //     assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - amountRepaid, "this balance");
    //     assertEq(borrowableAsset.balanceOf(address(blue)), amountRepaid, "blue balance");
    // }

    // function testRepayAmount(uint256 amountBorrowed, uint256 exactAmountRepaid) public {
    //     _testRepayCommon(amountBorrowed, address(this));

    //     uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
    //     uint256 borrowSharesBefore = blue.borrowShares(id, address(this));
    //     exactAmountRepaid = bound(
    //         exactAmountRepaid, 1, borrowSharesBefore.toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id))
    //     );
    //     uint256 sharesRepaid = exactAmountRepaid.toSharesDown(blue.totalBorrow(id), blue.totalBorrowShares(id));
    //     blue.repay(marketParams, exactAmountRepaid, 0, address(this), hex"");

    //     assertEq(blue.borrowShares(id, address(this)), borrowSharesBefore - sharesRepaid, "borrow share");
    //     assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - exactAmountRepaid, "this balance");
    //     assertEq(borrowableAsset.balanceOf(address(blue)), exactAmountRepaid, "blue balance");
    // }

    // function testRepayAll(uint256 amountBorrowed) public {
    //     _testRepayCommon(amountBorrowed, address(this));

    //     uint256 amountRepaid =
    //         blue.borrowShares(id, address(this)).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
    //     borrowableAsset.setBalance(address(this), amountRepaid);
    //     blue.repay(marketParams, 0, blue.borrowShares(id, address(this)), address(this), hex"");

    //     assertEq(blue.borrowShares(id, address(this)), 0, "borrow share");
    //     assertEq(borrowableAsset.balanceOf(address(this)), 0, "this balance");
    //     assertEq(borrowableAsset.balanceOf(address(blue)), amountRepaid, "blue balance");
    // }

    function testSupplyCollateralOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        blue.supplyCollateral(marketParams, amount, onBehalf, hex"");

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
        blue.supplyCollateral(marketParams, amountDeposited, address(this), hex"");

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(marketParams, amountWithdrawn, address(this), receiver);
            return;
        }

        blue.withdrawCollateral(marketParams, amountWithdrawn, address(this), receiver);

        assertEq(blue.collateral(id, address(this)), amountDeposited - amountWithdrawn, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(blue)), amountDeposited - amountWithdrawn, "blue balance");
    }

    function testWithdrawCollateralAll(uint256 amountDeposited, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        blue.supplyCollateral(marketParams, amountDeposited, address(this), hex"");
        blue.withdrawCollateral(marketParams, blue.collateral(id, address(this)), address(this), receiver);

        assertEq(blue.collateral(id, address(this)), 0, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), amountDeposited, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(blue)), 0, "blue balance");
    }

    function testCollateralRequirements(uint256 amountCollateral, uint256 amountBorrowed, uint256 collateralPrice)
        public
    {
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        amountCollateral = bound(amountCollateral, 1, 2 ** 64);
        collateralPrice = bound(collateralPrice, 0, 2 ** 64);

        oracle.setPrice(collateralPrice);

        borrowableAsset.setBalance(address(this), amountBorrowed);
        collateralAsset.setBalance(BORROWER, amountCollateral);

        blue.supply(marketParams, amountBorrowed, 0, address(this), hex"");

        vm.prank(BORROWER);
        blue.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");

        uint256 maxBorrow = amountCollateral.wMulDown(collateralPrice).wMulDown(LLTV);

        vm.prank(BORROWER);
        if (maxBorrow < amountBorrowed) vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        blue.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
    }

    function testLiquidate(uint256 amountLent) public {
        oracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.wMulDown(LLTV);
        uint256 amountBorrowed = borrowingPower.wMulDown(0.8e18);
        uint256 toSeize = amountCollateral.wMulDown(LLTV);
        uint256 incentive = WAD + ALPHA.wMulDown(WAD.wDivDown(LLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(marketParams, amountLent, 0, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        blue.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        oracle.setPrice(0.5e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(marketParams, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);
        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        uint256 expectedRepaid = toSeize.mulDivUp(collateralPrice, priceScale).wDivUp(incentive);
        uint256 expectedNetWorthAfter =
            liquidatorNetWorthBefore + toSeize.mulDivDown(collateralPrice, priceScale) - expectedRepaid;
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(blue.collateral(id, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 amountLent) public {
        oracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.wMulDown(LLTV);
        uint256 amountBorrowed = borrowingPower.wMulDown(0.8e18);
        uint256 toSeize = amountCollateral;
        uint256 incentive = WAD + ALPHA.wMulDown(WAD.wDivDown(marketParams.lltv) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(marketParams, amountLent, 0, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        blue.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        oracle.setPrice(0.01e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        blue.liquidate(marketParams, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);
        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        uint256 expectedRepaid = toSeize.mulDivUp(collateralPrice, priceScale).wDivUp(incentive);
        uint256 expectedNetWorthAfter =
            liquidatorNetWorthBefore + toSeize.mulDivDown(collateralPrice, priceScale) - expectedRepaid;
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
        blue.supply(marketParams, firstAmount, 0, address(this), hex"");

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        blue.supply(marketParams, secondAmount, 0, BORROWER, hex"");

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(
            blue.supplyShares(id, address(this)),
            firstAmount * SharesMathLib.VIRTUAL_SHARES,
            "expected shares first user"
        );
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertApproxEqAbs(
            blue.supplyShares(id, BORROWER),
            secondAmount * SharesMathLib.VIRTUAL_SHARES,
            100,
            "expected shares second user"
        );
    }

    function testUnknownMarket(MarketParams memory marketFuzz) public {
        vm.assume(neq(marketFuzz, marketParams));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.supply(marketFuzz, 1, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.withdraw(marketFuzz, 1, 0, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.borrow(marketFuzz, 1, 0, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.repay(marketFuzz, 1, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.supplyCollateral(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.withdrawCollateral(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.liquidate(marketFuzz, address(0), 1, hex"");
    }

    function testInputZero() public {
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.supply(marketParams, 0, 0, address(this), hex"");
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.supply(marketParams, 1, 1, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.withdraw(marketParams, 0, 0, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.withdraw(marketParams, 1, 1, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.borrow(marketParams, 0, 0, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.borrow(marketParams, 1, 1, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.repay(marketParams, 0, 0, address(this), hex"");
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.repay(marketParams, 1, 1, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        blue.supplyCollateral(marketParams, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        blue.withdrawCollateral(marketParams, 0, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        blue.liquidate(marketParams, address(0), 0, hex"");
    }

    function testZeroAddress() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.supply(marketParams, 0, 1, address(0), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.withdraw(marketParams, 0, 1, address(this), address(0));

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.borrow(marketParams, 0, 1, address(this), address(0));

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.repay(marketParams, 0, 1, address(0), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.supplyCollateral(marketParams, 1, address(0), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.withdrawCollateral(marketParams, 1, address(this), address(0));
    }

    function testEmptyMarket(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max / SharesMathLib.VIRTUAL_SHARES);

        vm.expectRevert(stdError.arithmeticError);
        blue.withdraw(marketParams, amount, 0, address(this), address(this));

        vm.expectRevert(stdError.arithmeticError);
        blue.repay(marketParams, amount, 0, address(this), hex"");

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(marketParams, amount, address(this), address(this));
    }

    function testSetAuthorization(address authorized, bool isAuthorized) public {
        blue.setAuthorization(authorized, isAuthorized);
        assertEq(blue.isAuthorized(address(this), authorized), isAuthorized);
    }

    function testNotAuthorized(address attacker) public {
        vm.assume(attacker != address(this));

        vm.startPrank(attacker);

        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        blue.withdraw(marketParams, 0, 1, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        blue.withdrawCollateral(marketParams, 1, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        blue.borrow(marketParams, 0, 1, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorization(address authorized) public {
        borrowableAsset.setBalance(address(this), 100 ether);
        collateralAsset.setBalance(address(this), 100 ether);

        blue.supply(marketParams, 100 ether, 0, address(this), hex"");
        blue.supplyCollateral(marketParams, 100 ether, address(this), hex"");

        blue.setAuthorization(authorized, true);

        vm.startPrank(authorized);

        blue.withdraw(marketParams, 1 ether, 0, address(this), address(this));
        blue.withdrawCollateral(marketParams, 1 ether, address(this), address(this));
        blue.borrow(marketParams, 1 ether, 0, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorizationWithSig(uint32 deadline, address authorized, uint256 privateKey, bool isAuthorized)
        public
    {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));
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

        blue.setAuthorizationWithSig(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );

        assertEq(blue.isAuthorized(authorizer, authorized), isAuthorized);
        assertEq(blue.nonce(authorizer), 1);
    }

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, amount, 0, address(this), hex"");

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
        blue.supply(marketParams, amount, 0, address(this), hex"");
        blue.supply(marketParams, amount, 0, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(address(this), amount);
        collateralAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supplyCollateral(marketParams, amount, address(this), hex"");
        blue.supplyCollateral(
            marketParams, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, amount, 0, address(this), hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        blue.supplyCollateral(marketParams, collateralAmount, address(this), hex"");
        blue.borrow(marketParams, amount, 0, address(this), address(this));

        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        blue.repay(marketParams, amount, 0, address(this), hex"");
        blue.repay(marketParams, amount, 0, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(marketParams, amount, 0, address(this), hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        blue.supplyCollateral(marketParams, collateralAmount, address(this), hex"");
        blue.borrow(marketParams, amount.wMulDown(LLTV), 0, address(this), address(this));

        oracle.setPrice(0.5e18);

        borrowableAsset.setBalance(address(this), amount);
        borrowableAsset.approve(address(blue), 0);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        blue.liquidate(marketParams, address(this), collateralAmount, hex"");
        blue.liquidate(marketParams, address(this), collateralAmount, abi.encode(this.testLiquidateCallback.selector, hex""));
    }

    function testFlashActions(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);
        oracle.setPrice(1e18);
        uint256 toBorrow = amount.wMulDown(LLTV);

        borrowableAsset.setBalance(address(this), 2 * toBorrow);
        blue.supply(marketParams, toBorrow, 0, address(this), hex"");

        blue.supplyCollateral(
            marketParams, amount, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(blue.borrowShares(marketParams.id(), address(this)), 0, "no borrow");

        blue.repay(
            marketParams,
            0,
            blue.borrowShares(id, address(this)),
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(amount))
        );
        assertEq(blue.collateral(marketParams.id(), address(this)), 0, "no withdraw collateral");
    }

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
            borrowableAsset.setBalance(address(this), toBorrow);
            blue.borrow(marketParams, toBorrow, 0, address(this), address(this));
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
            blue.withdrawCollateral(marketParams, toWithdraw, address(this), address(this));
        }
    }

    function onBlueLiquidate(uint256 repaid, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            borrowableAsset.approve(address(blue), repaid);
        }
    }

    function onBlueFlashLoan(uint256 amount, bytes calldata) external {
        borrowableAsset.approve(address(blue), amount);
    }
}

function neq(MarketParams memory a, MarketParams memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset || a.oracle != b.oracle
        || a.lltv != b.lltv || a.irm != b.irm;
}
