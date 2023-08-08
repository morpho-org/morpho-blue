// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SigUtils} from "./helpers/SigUtils.sol";

import "src/Morpho.sol";
import {SharesMath} from "src/libraries/SharesMath.sol";
import {MorphoLib} from "src/libraries/MorphoLib.sol";
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
    using MorphoLib for IMorpho;
    using MarketLib for Market;
    using SharesMath for uint256;
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    address private constant BORROWER = address(1234);
    address private constant LIQUIDATOR = address(5678);
    uint256 private constant LLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);

    IMorpho private morpho;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    Irm private irm;
    Market public market;
    Id public id;

    function setUp() public {
        // Create Morpho.
        morpho = new Morpho(OWNER);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();

        irm = new Irm(morpho);

        market = Market(
            address(borrowableAsset),
            address(collateralAsset),
            address(borrowableOracle),
            address(collateralOracle),
            address(irm),
            LLTV
        );
        id = market.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);
        morpho.createMarket(market);
        vm.stopPrank();

        // We set the price of the borrowable asset to zero so that borrowers
        // don't need to deposit any collateral.
        borrowableOracle.setPrice(0);
        collateralOracle.setPrice(1e18);

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

    // To move to a test utils file later.

    function netWorth(address user) internal view returns (uint256) {
        uint256 collateralAssetValue = collateralAsset.balanceOf(user).mulWadDown(collateralOracle.price());
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user).mulWadDown(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = morpho.supplyShares(id, user);
        if (supplyShares == 0) return 0;

        uint256 totalShares = morpho.totalSupplyShares(id);
        uint256 totalSupply = morpho.totalSupply(id);
        return supplyShares.divWadDown(totalShares).mulWadDown(totalSupply);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = morpho.borrowShares(id, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = morpho.totalBorrowShares(id);
        uint256 totalBorrow = morpho.totalBorrow(id);
        return borrowerShares.divWadUp(totalShares).mulWadUp(totalBorrow);
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
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        morpho2.setOwner(newOwner);
    }

    function testEnableIrmWhenNotOwner(address attacker, address newIrm) public {
        vm.assume(attacker != morpho.owner());

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
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
        vm.expectRevert(bytes(Errors.IRM_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
    }

    function testEnableLltvWhenNotOwner(address attacker, uint256 newLltv) public {
        vm.assume(attacker != OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        morpho.enableLltv(newLltv);
    }

    function testEnableLltv(uint256 newLltv) public {
        newLltv = bound(newLltv, 0, FixedPointMathLib.WAD - 1);

        vm.prank(OWNER);
        morpho.enableLltv(newLltv);

        assertTrue(morpho.isLltvEnabled(newLltv));
    }

    function testEnableLltvShouldFailWhenLltvTooHigh(uint256 newLltv) public {
        newLltv = bound(newLltv, FixedPointMathLib.WAD, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_TOO_HIGH));
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
        vm.expectRevert(bytes(Errors.MAX_FEE_EXCEEDED));
        morpho.setFee(market, fee);
    }

    function testSetFeeShouldRevertIfMarketNotCreated(Market memory marketFuzz, uint256 fee) public {
        vm.assume(neq(marketFuzz, market));
        fee = bound(fee, 0, FixedPointMathLib.WAD);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.setFee(marketFuzz, fee);
    }

    function testSetFeeShouldRevertIfNotOwner(uint256 fee, address caller) public {
        vm.assume(caller != OWNER);
        fee = bound(fee, 0, FixedPointMathLib.WAD);

        vm.expectRevert(bytes(Errors.NOT_OWNER));
        morpho.setFee(market, fee);
    }

    function testSetFeeRecipient(address recipient) public {
        vm.prank(OWNER);
        morpho.setFeeRecipient(recipient);

        assertEq(morpho.feeRecipient(), recipient);
    }

    function testSetFeeRecipientShouldRevertIfNotOwner(address caller, address recipient) public {
        vm.assume(caller != OWNER);

        vm.expectRevert(bytes(Errors.NOT_OWNER));
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
        morpho.supply(market, amountLent, address(this), hex"");

        vm.prank(BORROWER);
        morpho.borrow(market, amountBorrowed, BORROWER, BORROWER);

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
        uint256 expectedFee = accrued.mulWadDown(fee);
        uint256 expectedFeeShares = expectedFee.mulDivDown(totalSupplySharesBefore, totalSupplyAfter - expectedFee);

        assertEq(morpho.supplyShares(id, recipient), expectedFeeShares);
    }

    function testCreateMarketWithNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = address(irm);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_NOT_ENABLED));
        morpho.createMarket(marketFuzz);
    }

    function testSupplyOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(morpho));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, onBehalf, hex"");

        assertEq(morpho.supplyShares(id, onBehalf), amount * SharesMath.VIRTUAL_SHARES, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amount, "morpho balance");
    }

    function testBorrow(uint256 amountLent, uint256 amountBorrowed, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(morpho));
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        morpho.supply(market, amountLent, address(this), hex"");

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            morpho.borrow(market, amountBorrowed, BORROWER, receiver);
            return;
        }

        vm.prank(BORROWER);
        morpho.borrow(market, amountBorrowed, BORROWER, receiver);

        assertEq(morpho.borrowShares(id, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow share");
        assertEq(borrowableAsset.balanceOf(receiver), amountBorrowed, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountLent - amountBorrowed, "morpho balance");
    }

    function _testWithdrawCommon(uint256 amountLent) public {
        amountLent = bound(amountLent, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        morpho.supply(market, amountLent, address(this), hex"");

        // Accrue interests.
        stdstore.target(address(morpho)).sig("totalSupply(bytes32)").with_key(Id.unwrap(id)).checked_write(
            morpho.totalSupply(id) * 4 / 3
        );
        borrowableAsset.setBalance(address(morpho), morpho.totalSupply(id));
    }

    function testWithdrawShares(uint256 amountLent, uint256 sharesWithdrawn, uint256 amountBorrowed, address receiver)
        public
    {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(morpho));
        vm.assume(receiver != address(this));
        sharesWithdrawn = bound(sharesWithdrawn, 1, 2 ** 64);

        _testWithdrawCommon(amountLent);
        amountBorrowed = bound(amountBorrowed, 1, morpho.totalSupply(id));
        morpho.borrow(market, amountBorrowed, BORROWER, BORROWER);

        uint256 totalSupplyBefore = morpho.totalSupply(id);
        uint256 supplySharesBefore = morpho.supplyShares(id, address(this));
        uint256 amountWithdrawn = sharesWithdrawn.toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));

        if (sharesWithdrawn > morpho.supplyShares(id, address(this))) {
            vm.expectRevert(stdError.arithmeticError);
            morpho.withdraw(market, sharesWithdrawn, address(this), receiver);
            return;
        } else if (amountWithdrawn > totalSupplyBefore - amountBorrowed) {
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            morpho.withdraw(market, sharesWithdrawn, address(this), receiver);
            return;
        }

        morpho.withdraw(market, sharesWithdrawn, address(this), receiver);

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
        uint256 sharesWithdrawn = morpho.withdrawAmount(market, exactAmountWithdrawn, address(this), address(this));

        assertEq(morpho.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), exactAmountWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), totalSupplyBefore - exactAmountWithdrawn, "morpho balance");
    }

    function testWithdrawAll(uint256 amountLent) public {
        _testWithdrawCommon(amountLent);

        uint256 totalSupplyBefore = morpho.totalSupply(id);
        uint256 amountWithdrawn =
            morpho.supplyShares(id, address(this)).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));
        morpho.withdraw(market, morpho.supplyShares(id, address(this)), address(this), address(this));

        assertEq(morpho.supplyShares(id, address(this)), 0, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), totalSupplyBefore - amountWithdrawn, "morpho balance");
    }

    function _testRepayCommon(uint256 amountBorrowed, address borrower) public {
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), 2 ** 66);
        morpho.supply(market, amountBorrowed, address(this), hex"");
        vm.prank(borrower);
        morpho.borrow(market, amountBorrowed, borrower, borrower);

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
        morpho.repay(market, sharesRepaid, onBehalf, hex"");

        assertEq(morpho.borrowShares(id, onBehalf), borrowSharesBefore - sharesRepaid, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - amountRepaid, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amountRepaid, "morpho balance");
    }

    function testRepayAmount(uint256 amountBorrowed, uint256 exactAmountRepaid) public {
        _testRepayCommon(amountBorrowed, address(this));

        uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
        uint256 borrowSharesBefore = morpho.borrowShares(id, address(this));
        exactAmountRepaid = bound(
            exactAmountRepaid, 1, borrowSharesBefore.toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id))
        );
        uint256 sharesRepaid = morpho.repayAmount(market, exactAmountRepaid, address(this), hex"");

        assertEq(morpho.borrowShares(id, address(this)), borrowSharesBefore - sharesRepaid, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - exactAmountRepaid, "this balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), exactAmountRepaid, "morpho balance");
    }

    function testRepayAll(uint256 amountBorrowed) public {
        _testRepayCommon(amountBorrowed, address(this));

        uint256 amountRepaid =
            morpho.borrowShares(id, address(this)).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        borrowableAsset.setBalance(address(this), amountRepaid);
        morpho.repay(market, morpho.borrowShares(id, address(this)), address(this), hex"");

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

        morpho.supply(market, amountBorrowed, address(this), hex"");

        vm.prank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");

        uint256 collateralValue = amountCollateral.mulWadDown(priceCollateral);
        uint256 borrowValue = amountBorrowed.mulWadUp(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.mulWadDown(LLTV))) {
            vm.prank(BORROWER);
            morpho.borrow(market, amountBorrowed, BORROWER, BORROWER);
        } else {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
            morpho.borrow(market, amountBorrowed, BORROWER, BORROWER);
        }
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
        morpho.supply(market, amountLent, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        morpho.liquidate(market, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(morpho.collateral(id, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
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
        morpho.supply(market, amountLent, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, BORROWER, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(100e18);

        uint256 liquidatorNetWorthBefore = netWorth(LIQUIDATOR);

        // Liquidate
        vm.prank(LIQUIDATOR);
        morpho.liquidate(market, BORROWER, toSeize, hex"");

        uint256 liquidatorNetWorthAfter = netWorth(LIQUIDATOR);

        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
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
        morpho.supply(market, firstAmount, address(this), hex"");

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        morpho.supply(market, secondAmount, BORROWER, hex"");

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(
            morpho.supplyShares(id, address(this)),
            firstAmount * SharesMath.VIRTUAL_SHARES,
            "expected shares first user"
        );
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertApproxEqAbs(
            morpho.supplyShares(id, BORROWER),
            secondAmount * SharesMath.VIRTUAL_SHARES,
            100,
            "expected shares second user"
        );
    }

    function testUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.supply(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.withdraw(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.borrow(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.repay(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.supplyCollateral(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.withdrawCollateral(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        morpho.liquidate(marketFuzz, address(0), 1, hex"");
    }

    function testInputZero() public {
        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        morpho.supply(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_SHARES));
        morpho.withdraw(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        morpho.borrow(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_SHARES));
        morpho.repay(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        morpho.supplyCollateral(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        morpho.withdrawCollateral(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        morpho.liquidate(market, address(0), 0, hex"");
    }

    function testZeroAddress() public {
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        morpho.supply(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        morpho.withdraw(market, 1, address(this), address(0));

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        morpho.borrow(market, 1, address(this), address(0));

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        morpho.repay(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        morpho.supplyCollateral(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        morpho.withdrawCollateral(market, 1, address(this), address(0));
    }

    function testEmptyMarket(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max / SharesMath.VIRTUAL_SHARES);

        vm.expectRevert(stdError.arithmeticError);
        morpho.withdraw(market, amount, address(this), address(this));

        vm.expectRevert(stdError.arithmeticError);
        morpho.repay(market, amount, address(this), hex"");

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

        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        morpho.withdraw(market, 1, address(this), address(this));
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        morpho.withdrawCollateral(market, 1, address(this), address(this));
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        morpho.borrow(market, 1, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorization(address authorized) public {
        borrowableAsset.setBalance(address(this), 100 ether);
        collateralAsset.setBalance(address(this), 100 ether);

        morpho.supply(market, 100 ether, address(this), hex"");
        morpho.supplyCollateral(market, 100 ether, address(this), hex"");

        morpho.setAuthorization(authorized, true);

        vm.startPrank(authorized);

        morpho.withdraw(market, 1 ether, address(this), address(this));
        morpho.withdrawCollateral(market, 1 ether, address(this), address(this));
        morpho.borrow(market, 1 ether, address(this), address(this));

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
            nonce: morpho.nonce(authorizer),
            deadline: block.timestamp + deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        morpho.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );

        assertEq(morpho.isAuthorized(authorizer, authorized), isAuthorized);
        assertEq(morpho.nonce(authorizer), 1);
    }

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, address(this), hex"");

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
        morpho.supply(market, amount, address(this), hex"");
        morpho.supply(market, amount, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
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
        morpho.supply(market, amount, address(this), hex"");
        morpho.borrow(market, amount, address(this), address(this));

        borrowableAsset.approve(address(morpho), 0);

        vm.expectRevert();
        morpho.repay(market, amount, address(this), hex"");
        morpho.repay(market, amount, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);
        borrowableOracle.setPrice(1e18);
        borrowableAsset.setBalance(address(this), amount);
        collateralAsset.setBalance(address(this), amount);
        morpho.supply(market, amount, address(this), hex"");
        morpho.supplyCollateral(market, amount, address(this), hex"");
        morpho.borrow(market, amount.mulWadDown(LLTV), address(this), address(this));

        borrowableOracle.setPrice(1.01e18);

        uint256 toSeize = amount.mulWadDown(LLTV);

        borrowableAsset.setBalance(address(this), toSeize);
        borrowableAsset.approve(address(morpho), 0);
        vm.expectRevert();
        morpho.liquidate(market, address(this), toSeize, hex"");
        morpho.liquidate(market, address(this), toSeize, abi.encode(this.testLiquidateCallback.selector, hex""));
    }

    function testFlashActions(uint256 amount) public {
        amount = bound(amount, 10, 2 ** 64);
        borrowableOracle.setPrice(1e18);
        uint256 toBorrow = amount.mulWadDown(LLTV);

        borrowableAsset.setBalance(address(this), 2 * toBorrow);
        morpho.supply(market, toBorrow, address(this), hex"");

        morpho.supplyCollateral(
            market, amount, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(morpho.borrowShares(market.id(), address(this)), 0, "no borrow");

        morpho.repay(
            market,
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
            morpho.borrow(market, toBorrow, address(this), address(this));
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

    function onMorphoLiquidate(uint256, uint256 repaid, bytes memory data) external {
        require(msg.sender == address(morpho));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            borrowableAsset.approve(address(morpho), repaid);
        }
    }

    function onMorphoFlashLoan(address token, uint256 amount, bytes calldata) external {
        ERC20(token).approve(address(morpho), amount);
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lltv != b.lltv
        || a.irm != b.irm;
}
