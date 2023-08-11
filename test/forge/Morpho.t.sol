// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SigUtils} from "./helpers/SigUtils.sol";

import "src/Morpho.sol";
import {SharesMathLib} from "src/libraries/SharesMathLib.sol";
import {
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback
} from "src/interfaces/IMorphoCallbacks.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract MorphoTest is
    Test,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback,
    IMorphoRepayCallback,
    IMorphoLiquidateCallback
{
    using MarketLib for Market;
    using SharesMathLib for uint256;
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    address private constant BORROWER = address(0x1234);
    address private constant LIQUIDATOR = address(0x5678);
    uint256 private constant LLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);

    IMorpho private morpho;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private oracle;
    Irm private irm;
    Market private market;
    Id private id;

    function setUp() public {
        // Create Morpho.
        morpho = new Morpho(OWNER);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        oracle = new Oracle();

        irm = new Irm(morpho);

        market = Market(address(borrowableAsset), address(collateralAsset), address(oracle), address(irm), LLTV);
        id = market.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);
        morpho.createMarket(market);
        vm.stopPrank();

        oracle.setPrice(WAD);

        borrowableAsset.approve(address(morpho), type(uint256).max);
        collateralAsset.approve(address(morpho), type(uint256).max);

        vm.startPrank(BORROWER);
        borrowableAsset.approve(address(morpho), type(uint256).max);
        collateralAsset.approve(address(morpho), type(uint256).max);
        morpho.setAuthorization(address(this), true);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        borrowableAsset.approve(address(morpho), type(uint256).max);
        collateralAsset.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Calculates the net worth of the given user quoted in borrowable asset.
    // TODO: To move to a test utils file later.
    function netWorth(address user) internal view returns (uint256) {
        (uint256 collateralPrice, uint256 priceScale) = IOracle(market.oracle).price();

        uint256 collateralAssetValue = collateralAsset.balanceOf(user).mulDivDown(collateralPrice, priceScale);
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user);

        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = morpho.supplyShares(id, user);
        if (supplyShares == 0) return 0;

        uint256 totalShares = morpho.totalSupplyShares(id);
        uint256 totalSupply = morpho.totalSupply(id);
        return supplyShares.wDivDown(totalShares).wMulDown(totalSupply);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = morpho.borrowShares(id, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = morpho.totalBorrowShares(id);
        uint256 totalBorrow = morpho.totalBorrow(id);
        return borrowerShares.wDivUp(totalShares).wMulUp(totalBorrow);
    }

    // Invariants

    function invariantLiquidity() public {
        assertLe(morpho.totalBorrow(id), morpho.totalSupply(id), "liquidity");
    }

    function invariantLltvEnabled() public {
        assertTrue(morpho.isLltvEnabled(LLTV));
    }

    function invariantIrmEnabled() public {
        assertTrue(morpho.isIrmEnabled(address(irm)));
    }

    function invariantMarketCreated() public {
        assertGt(morpho.lastUpdate(id), 0);
    }

    // Tests

    function testOwner(address newOwner) public {
        Morpho morpho2 = new Morpho(newOwner);

        assertEq(morpho2.owner(), newOwner, "owner");
    }

    function testTransferOwnership(address oldOwner, address newOwner) public {
        Morpho morpho2 = new Morpho(oldOwner);

        vm.prank(oldOwner);
        morpho2.setOwner(newOwner);
        assertEq(morpho2.owner(), newOwner, "owner");
    }

    function testTransferOwnershipWhenNotOwner(address attacker, address newOwner) public {
        vm.assume(attacker != OWNER);

        Morpho morpho2 = new Morpho(OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho2.setOwner(newOwner);
    }

    function testEnableIrmWhenNotOwner(address attacker, address newIrm) public {
        vm.assume(attacker != morpho.owner());

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.enableIrm(newIrm);
    }

    function testEnableIrm(address newIrm) public {
        vm.prank(OWNER);
        morpho.enableIrm(newIrm);

        assertTrue(morpho.isIrmEnabled(newIrm));
    }

    function testCreateMarketWithEnabledIrm(Market memory marketFuzz) public {
        marketFuzz.lltv = LLTV;

        vm.startPrank(OWNER);
        morpho.enableIrm(marketFuzz.irm);
        morpho.createMarket(marketFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithNotEnabledIrm(Market memory marketFuzz) public {
        vm.assume(marketFuzz.irm != address(irm));

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
    }

    function testEnableLltvWhenNotOwner(address attacker, uint256 newLltv) public {
        vm.assume(attacker != OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.enableLltv(newLltv);
    }

    function testEnableLltv(uint256 newLltv) public {
        newLltv = bound(newLltv, 0, WAD - 1);

        vm.prank(OWNER);
        morpho.enableLltv(newLltv);

        assertTrue(morpho.isLltvEnabled(newLltv));
    }

    function testEnableLltvShouldFailWhenLltvTooHigh(uint256 newLltv) public {
        newLltv = bound(newLltv, WAD, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.LLTV_TOO_HIGH));
        morpho.enableLltv(newLltv);
    }

    function testSetFee(uint256 fee) public {
        fee = bound(fee, 0, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(market, fee);

        assertEq(morpho.fee(id), fee);
    }

    function testSetFeeShouldRevertIfTooHigh(uint256 fee) public {
        fee = bound(fee, MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MAX_FEE_EXCEEDED));
        morpho.setFee(market, fee);
    }

    function testSetFeeShouldRevertIfMarketNotCreated(Market memory marketFuzz, uint256 fee) public {
        vm.assume(neq(marketFuzz, market));
        fee = bound(fee, 0, WAD);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.setFee(marketFuzz, fee);
    }

    function testSetFeeShouldRevertIfNotOwner(uint256 fee, address caller) public {
        vm.assume(caller != OWNER);
        fee = bound(fee, 0, WAD);

        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.setFee(market, fee);
    }

    function testSetFeeRecipient(address recipient) public {
        vm.prank(OWNER);
        morpho.setFeeRecipient(recipient);

        assertEq(morpho.feeRecipient(), recipient);
    }

    function testSetFeeRecipientShouldRevertIfNotOwner(address caller, address recipient) public {
        vm.assume(caller != OWNER);

        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        vm.prank(caller);
        morpho.setFeeRecipient(recipient);
    }

    function testFeeAccrues(uint256 amountLent, uint256 amountBorrowed, uint256 fee, uint256 timeElapsed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        timeElapsed = bound(timeElapsed, 1, 365 days);
        fee = bound(fee, 0, MAX_FEE);
        address recipient = OWNER;

        vm.startPrank(OWNER);
        morpho.setFee(market, fee);
        morpho.setFeeRecipient(recipient);
        vm.stopPrank();

        borrowableAsset.setBalance(address(this), amountLent);
        morpho.supply(market, amountLent, 0, address(this), hex"");

        uint256 collateralAmount = amountBorrowed.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, BORROWER, hex"");

        vm.prank(BORROWER);
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);

        uint256 totalSupplyBefore = morpho.totalSupply(id);
        uint256 totalSupplySharesBefore = morpho.totalSupplyShares(id);

        // Trigger an accrue.
        vm.warp(block.timestamp + timeElapsed);

        collateralAsset.setBalance(address(this), 1);
        morpho.supplyCollateral(market, 1, address(this), hex"");
        morpho.withdrawCollateral(market, 1, address(this), address(this));

        uint256 totalSupplyAfter = morpho.totalSupply(id);
        vm.assume(totalSupplyAfter > totalSupplyBefore);

        uint256 accrued = totalSupplyAfter - totalSupplyBefore;
        uint256 expectedFee = accrued.wMulDown(fee);
        uint256 expectedFeeShares = expectedFee.mulDivDown(totalSupplySharesBefore, totalSupplyAfter - expectedFee);

        assertEq(morpho.supplyShares(id, recipient), expectedFeeShares);
    }

    function testCreateMarketWithNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = address(irm);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
    }

    function testSupplyAmount(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(morpho));
        amount = bound(amount, 1, 2 ** 64);
        uint256 shares = amount.toSharesDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, onBehalf, hex"");

        assertEq(morpho.supplyShares(id, onBehalf), shares, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amount, "morpho balance");
    }

    function testSupplyShares(uint256 shares, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(morpho));
        shares = bound(shares, 1, 2 ** 64);
        uint256 amount = shares.toAssetsUp(morpho.totalSupply(id), morpho.totalSupplyShares(id));

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, 0, shares, onBehalf, hex"");

        assertEq(morpho.supplyShares(id, onBehalf), shares, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amount, "morpho balance");
    }

    function testBorrowAmount(uint256 amountLent, uint256 amountBorrowed, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(morpho));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        uint256 shares = amountBorrowed.toSharesUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));

        borrowableAsset.setBalance(address(this), amountLent);
        morpho.supply(market, amountLent, 0, address(this), hex"");

        uint256 collateralAmount = shares.toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id)).wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, BORROWER, hex"");

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
            morpho.borrow(market, amountBorrowed, 0, BORROWER, receiver);
            return;
        }

        vm.prank(BORROWER);
        morpho.borrow(market, amountBorrowed, 0, BORROWER, receiver);

        assertEq(morpho.borrowShares(id, BORROWER), amountBorrowed * SharesMathLib.VIRTUAL_SHARES, "borrow share");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountLent - amountBorrowed, "morpho balance");
    }

    function testBorrowShares(uint256 shares) public {
        shares = bound(shares, 1, 2 ** 64);
        uint256 amount = shares.toAssetsDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id));

        borrowableAsset.setBalance(address(this), amount);
        if (amount > 0) morpho.supply(market, amount, 0, address(this), hex"");

        uint256 collateralAmount = shares.toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id)).wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        if (collateralAmount > 0) morpho.supplyCollateral(market, collateralAmount, BORROWER, hex"");

        vm.prank(BORROWER);
        morpho.borrow(market, 0, shares, BORROWER, BORROWER);

        assertEq(morpho.borrowShares(id, BORROWER), shares, "borrow share");
        assertEq(borrowableAsset.balanceOf(BORROWER), amount, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), 0, "morpho balance");
    }

    function _testWithdrawCommon(uint256 amountLent) public {
        amountLent = bound(amountLent, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        morpho.supply(market, amountLent, 0, address(this), hex"");

        // Accrue interests.
        stdstore.target(address(morpho)).sig("totalSupply(bytes32)").with_key(Id.unwrap(id)).checked_write(
            morpho.totalSupply(id) * 4 / 3
        );
        borrowableAsset.setBalance(address(morpho), morpho.totalSupply(id));
    }

    function testWithdrawShares(uint256 amountLent, uint256 sharesWithdrawn, uint256 amountBorrowed, address receiver)
        public
    {
        vm.assume(receiver != BORROWER);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(morpho));
        vm.assume(receiver != address(this));
        sharesWithdrawn = bound(sharesWithdrawn, 1, 2 ** 64);

        _testWithdrawCommon(amountLent);
        amountBorrowed = bound(amountBorrowed, 1, morpho.totalSupply(id));

        uint256 collateralAmount = amountBorrowed.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, BORROWER, hex"");

        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);

        uint256 totalSupplyBefore = morpho.totalSupply(id);
        uint256 supplySharesBefore = morpho.supplyShares(id, address(this));
        uint256 amountWithdrawn = sharesWithdrawn.toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));

        if (sharesWithdrawn > morpho.supplyShares(id, address(this))) {
            vm.expectRevert(stdError.arithmeticError);
            morpho.withdraw(market, 0, sharesWithdrawn, address(this), receiver);
            return;
        } else if (amountWithdrawn > totalSupplyBefore - amountBorrowed) {
            vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
            morpho.withdraw(market, 0, sharesWithdrawn, address(this), receiver);
            return;
        }

        morpho.withdraw(market, 0, sharesWithdrawn, address(this), receiver);

        assertEq(morpho.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
        assertEq(borrowableAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(morpho)),
            totalSupplyBefore - amountBorrowed - amountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawAmount(uint256 amountLent, uint256 exactAmountWithdrawn) public {
        _testWithdrawCommon(amountLent);

        uint256 totalSupplyBefore = morpho.totalSupply(id);
        uint256 supplySharesBefore = morpho.supplyShares(id, address(this));
        exactAmountWithdrawn = bound(
            exactAmountWithdrawn,
            1,
            supplySharesBefore.toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id))
        );
        morpho.withdraw(market, exactAmountWithdrawn, 0, address(this), address(this));

        // assertEq(morpho.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), exactAmountWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), totalSupplyBefore - exactAmountWithdrawn, "morpho balance");
    }

    function testWithdrawAll(uint256 amountLent) public {
        _testWithdrawCommon(amountLent);

        uint256 totalSupplyBefore = morpho.totalSupply(id);
        uint256 amountWithdrawn =
            morpho.supplyShares(id, address(this)).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));
        morpho.withdraw(market, 0, morpho.supplyShares(id, address(this)), address(this), address(this));

        assertEq(morpho.supplyShares(id, address(this)), 0, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), totalSupplyBefore - amountWithdrawn, "morpho balance");
    }

    function _testRepayCommon(uint256 amountBorrowed, address borrower) public {
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), 2 ** 66);
        morpho.supply(market, amountBorrowed, 0, address(this), hex"");

        uint256 collateralAmount = amountBorrowed.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, borrower, hex"");

        vm.prank(borrower);
        morpho.borrow(market, amountBorrowed, 0, borrower, borrower);

        // Accrue interests.
        stdstore.target(address(morpho)).sig("totalBorrow(bytes32)").with_key(Id.unwrap(id)).checked_write(
            morpho.totalBorrow(id) * 4 / 3
        );
    }

    function testRepayShares(uint256 amountBorrowed, uint256 sharesRepaid, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(morpho));
        _testRepayCommon(amountBorrowed, onBehalf);

        uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
        uint256 borrowSharesBefore = morpho.borrowShares(id, onBehalf);
        sharesRepaid = bound(sharesRepaid, 1, borrowSharesBefore);

        uint256 amountRepaid = sharesRepaid.toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        morpho.repay(market, 0, sharesRepaid, onBehalf, hex"");

        assertEq(morpho.borrowShares(id, onBehalf), borrowSharesBefore - sharesRepaid, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - amountRepaid, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountRepaid, "morpho balance");
    }

    function testRepayAmount(uint256 amountBorrowed, uint256 exactAmountRepaid) public {
        _testRepayCommon(amountBorrowed, address(this));

        uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
        uint256 borrowSharesBefore = morpho.borrowShares(id, address(this));
        exactAmountRepaid = bound(
            exactAmountRepaid, 1, borrowSharesBefore.toAssetsDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id))
        );
        uint256 sharesRepaid = exactAmountRepaid.toSharesDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        morpho.repay(market, exactAmountRepaid, 0, address(this), hex"");

        assertEq(morpho.borrowShares(id, address(this)), borrowSharesBefore - sharesRepaid, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - exactAmountRepaid, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), exactAmountRepaid, "morpho balance");
    }

    function testRepayAll(uint256 amountBorrowed) public {
        _testRepayCommon(amountBorrowed, address(this));

        uint256 amountRepaid =
            morpho.borrowShares(id, address(this)).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        borrowableAsset.setBalance(address(this), amountRepaid);
        morpho.repay(market, 0, morpho.borrowShares(id, address(this)), address(this), hex"");

        assertEq(morpho.borrowShares(id, address(this)), 0, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountRepaid, "morpho balance");
    }

    function testSupplyCollateralOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(morpho));
        amount = bound(amount, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amount);
        morpho.supplyCollateral(market, amount, onBehalf, hex"");

        assertEq(morpho.collateral(id, onBehalf), amount, "collateral");
        assertEq(collateralAsset.balanceOf(onBehalf), 0, "onBehalf balance");
        assertEq(collateralAsset.balanceOf(address(morpho)), amount, "morpho balance");
    }

    function testWithdrawCollateral(uint256 amountDeposited, uint256 amountWithdrawn, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(morpho));
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        morpho.supplyCollateral(market, amountDeposited, address(this), hex"");

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            morpho.withdrawCollateral(market, amountWithdrawn, address(this), receiver);
            return;
        }

        morpho.withdrawCollateral(market, amountWithdrawn, address(this), receiver);

        assertEq(morpho.collateral(id, address(this)), amountDeposited - amountWithdrawn, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(morpho)), amountDeposited - amountWithdrawn, "morpho balance");
    }

    function testWithdrawCollateralAll(uint256 amountDeposited, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(morpho));
        amountDeposited = bound(amountDeposited, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), amountDeposited);
        morpho.supplyCollateral(market, amountDeposited, address(this), hex"");
        morpho.withdrawCollateral(market, morpho.collateral(id, address(this)), address(this), receiver);

        assertEq(morpho.collateral(id, address(this)), 0, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), amountDeposited, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(morpho)), 0, "morpho balance");
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

        morpho.supply(market, amountBorrowed, 0, address(this), hex"");

        vm.prank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        uint256 maxBorrow = amountCollateral.wMulDown(collateralPrice).wMulDown(LLTV);

        vm.prank(BORROWER);
        if (maxBorrow < amountBorrowed) vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
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
        morpho.supply(market, amountLent, 0, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        oracle.setPrice(0.5e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        morpho.liquidate(market, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);
        (uint256 collateralPrice, uint256 priceScale) = IOracle(market.oracle).price();

        uint256 expectedRepaid = toSeize.mulDivUp(collateralPrice, priceScale).wDivUp(incentive);
        uint256 expectedNetWorthAfter =
            liquidatorNetWorthBefore + toSeize.mulDivDown(collateralPrice, priceScale) - expectedRepaid;
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(morpho.collateral(id, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 amountLent) public {
        oracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.wMulDown(LLTV);
        uint256 amountBorrowed = borrowingPower.wMulDown(0.8e18);
        uint256 toSeize = amountCollateral;
        uint256 incentive = WAD + ALPHA.wMulDown(WAD.wDivDown(market.lltv) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        morpho.supply(market, amountLent, 0, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        oracle.setPrice(0.01e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        morpho.liquidate(market, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);
        (uint256 collateralPrice, uint256 priceScale) = IOracle(market.oracle).price();

        uint256 expectedRepaid = toSeize.mulDivUp(collateralPrice, priceScale).wDivUp(incentive);
        uint256 expectedNetWorthAfter =
            liquidatorNetWorthBefore + toSeize.mulDivDown(collateralPrice, priceScale) - expectedRepaid;
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertEq(borrowBalance(BORROWER), 0, "BORROWER balance");
        assertEq(morpho.collateral(id, BORROWER), 0, "BORROWER collateral");
        uint256 expectedBadDebt = amountBorrowed - expectedRepaid;
        assertGt(expectedBadDebt, 0, "bad debt");
        assertApproxEqAbs(supplyBalance(address(this)), amountLent - expectedBadDebt, 10, "lender supply balance");
        assertApproxEqAbs(morpho.totalBorrow(id), 0, 10, "total borrow");
    }

    function testTwoUsersSupply(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        morpho.supply(market, firstAmount, 0, address(this), hex"");

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        morpho.supply(market, secondAmount, 0, BORROWER, hex"");

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(
            morpho.supplyShares(id, address(this)),
            firstAmount * SharesMathLib.VIRTUAL_SHARES,
            "expected shares first user"
        );
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertApproxEqAbs(
            morpho.supplyShares(id, BORROWER),
            secondAmount * SharesMathLib.VIRTUAL_SHARES,
            100,
            "expected shares second user"
        );
    }

    function testUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supply(marketFuzz, 1, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdraw(marketFuzz, 1, 0, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.borrow(marketFuzz, 1, 0, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.repay(marketFuzz, 1, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supplyCollateral(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdrawCollateral(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.liquidate(marketFuzz, address(0), 1, hex"");
    }

    function testInputZero() public {
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.supply(market, 0, 0, address(this), hex"");
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.supply(market, 1, 1, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.withdraw(market, 0, 0, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.withdraw(market, 1, 1, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.borrow(market, 0, 0, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.borrow(market, 1, 1, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.repay(market, 0, 0, address(this), hex"");
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.repay(market, 1, 1, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        morpho.supplyCollateral(market, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        morpho.withdrawCollateral(market, 0, address(this), address(this));

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        morpho.liquidate(market, address(0), 0, hex"");
    }

    function testZeroAddress() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supply(market, 0, 1, address(0), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdraw(market, 0, 1, address(this), address(0));

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.borrow(market, 0, 1, address(this), address(0));

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.repay(market, 0, 1, address(0), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supplyCollateral(market, 1, address(0), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdrawCollateral(market, 1, address(this), address(0));
    }

    function testEmptyMarket(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max / SharesMathLib.VIRTUAL_SHARES);

        vm.expectRevert(stdError.arithmeticError);
        morpho.withdraw(market, amount, 0, address(this), address(this));

        vm.expectRevert(stdError.arithmeticError);
        morpho.repay(market, amount, 0, address(this), hex"");

        vm.expectRevert(stdError.arithmeticError);
        morpho.withdrawCollateral(market, amount, address(this), address(this));
    }

    function testSetAuthorization(address authorized, bool isAuthorized) public {
        morpho.setAuthorization(authorized, isAuthorized);
        assertEq(morpho.isAuthorized(address(this), authorized), isAuthorized);
    }

    function testNotAuthorized(address attacker) public {
        vm.assume(attacker != address(this));

        vm.startPrank(attacker);

        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdraw(market, 0, 1, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdrawCollateral(market, 1, address(this), address(this));
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.borrow(market, 0, 1, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorization(address authorized) public {
        borrowableAsset.setBalance(address(this), 100 ether);
        collateralAsset.setBalance(address(this), 100 ether);

        morpho.supply(market, 100 ether, 0, address(this), hex"");
        morpho.supplyCollateral(market, 100 ether, address(this), hex"");

        morpho.setAuthorization(authorized, true);

        vm.startPrank(authorized);

        morpho.withdraw(market, 1 ether, 0, address(this), address(this));
        morpho.withdrawCollateral(market, 1 ether, address(this), address(this));
        morpho.borrow(market, 1 ether, 0, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorizationWithSig(Authorization memory authorization, uint256 privateKey) public {
        vm.assume(authorization.deadline > block.timestamp);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.nonce = 0;
        authorization.authorizer = vm.addr(privateKey);

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        morpho.setAuthorizationWithSig(authorization, sig);

        assertEq(morpho.isAuthorized(authorization.authorizer, authorization.authorized), authorization.isAuthorized);
        assertEq(morpho.nonce(authorization.authorizer), 1);
    }

    function testAuthorizationWithSigWrongSig(Authorization memory authorization, uint256 privateKey) public {
        vm.assume(authorization.deadline > block.timestamp);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.nonce = 1;
        authorization.authorizer = vm.addr(privateKey);

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        morpho.setAuthorizationWithSig(authorization, sig);

        assertEq(morpho.isAuthorized(authorization.authorizer, authorization.authorized), false);
        assertEq(morpho.nonce(authorization.authorizer), 0);
    }

    function testAuthorizationWithSigWrongNonce(Authorization memory authorization, uint256 privateKey) public {
        vm.assume(authorization.deadline > block.timestamp);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.nonce = 1;

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(bytes(ErrorsLib.INVALID_SIGNATURE));
        morpho.setAuthorizationWithSig(authorization, sig);
    }

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        morpho.flashLoan(address(borrowableAsset), amount, bytes(""));

        assertEq(borrowableAsset.balanceOf(address(morpho)), amount, "balanceOf");
    }

    function testExtsLoad(uint256 slot, bytes32 value0) public {
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = bytes32(slot);
        slots[1] = bytes32(slot / 2);

        bytes32 value1 = keccak256(abi.encode(value0));
        vm.store(address(morpho), slots[0], value0);
        vm.store(address(morpho), slots[1], value1);

        bytes32[] memory values = morpho.extsload(slots);

        assertEq(values.length, 2, "values.length");
        assertEq(values[0], slot > 0 ? value0 : value1, "value0");
        assertEq(values[1], value1, "value1");
    }

    function testSupplyCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(address(this), amount);
        borrowableAsset.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supply(market, amount, 0, address(this), hex"");
        morpho.supply(market, amount, 0, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(address(this), amount);
        collateralAsset.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.supplyCollateral(market, amount, address(this), hex"");
        morpho.supplyCollateral(
            market, amount, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, address(this), hex"");
        morpho.borrow(market, amount, 0, address(this), address(this));

        borrowableAsset.approve(address(morpho), 0);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        morpho.repay(market, amount, 0, address(this), hex"");
        morpho.repay(market, amount, 0, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);
        collateralAsset.setBalance(address(this), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, address(this), hex"");
        morpho.borrow(market, amount.wMulDown(LLTV), 0, address(this), address(this));

        oracle.setPrice(0.5e18);

        borrowableAsset.setBalance(address(this), amount);
        borrowableAsset.approve(address(morpho), 0);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        morpho.liquidate(market, address(this), collateralAmount, hex"");
        morpho.liquidate(
            market, address(this), collateralAmount, abi.encode(this.testLiquidateCallback.selector, hex"")
        );
    }

    function testFlashActions(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);
        oracle.setPrice(1e18);
        uint256 toBorrow = amount.wMulDown(LLTV);

        borrowableAsset.setBalance(address(this), 2 * toBorrow);
        morpho.supply(market, toBorrow, 0, address(this), hex"");

        morpho.supplyCollateral(
            market, amount, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(morpho.borrowShares(market.id(), address(this)), 0, "no borrow");

        morpho.repay(
            market,
            0,
            morpho.borrowShares(id, address(this)),
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(amount))
        );
        assertEq(morpho.collateral(market.id(), address(this)), 0, "no withdraw collateral");
    }

    // Callback functions.

    function onMorphoSupply(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            borrowableAsset.approve(address(morpho), amount);
        }
    }

    function onMorphoSupplyCollateral(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCollateralCallback.selector) {
            collateralAsset.approve(address(morpho), amount);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toBorrow = abi.decode(data, (uint256));
            collateralAsset.setBalance(address(this), amount);
            borrowableAsset.setBalance(address(this), toBorrow);
            morpho.borrow(market, toBorrow, 0, address(this), address(this));
        }
    }

    function onMorphoRepay(uint256 amount, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testRepayCallback.selector) {
            borrowableAsset.approve(address(morpho), amount);
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
            borrowableAsset.approve(address(morpho), repaid);
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes calldata) external {
        borrowableAsset.approve(address(morpho), amount);
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset || a.oracle != b.oracle
        || a.lltv != b.lltv || a.irm != b.irm;
}
