// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SigUtils} from "./helpers/SigUtils.sol";

import "src/Blue.sol";
import {SharesMath} from "src/libraries/SharesMath.sol";
import {BlueLib} from "src/libraries/BlueLib.sol";
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
    using BlueLib for IBlue;
    using MarketLib for Market;
    using SharesMath for uint256;
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    address private constant BORROWER = address(1234);
    address private constant LIQUIDATOR = address(5678);
    uint256 private constant LLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);

    IBlue private blue;
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
            address(borrowableAsset),
            address(collateralAsset),
            address(borrowableOracle),
            address(collateralOracle),
            address(irm),
            LLTV
        );
        id = market.id();

        vm.startPrank(OWNER);
        blue.enableIrm(address(irm));
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
        blue.setAuthorization(address(this), true);
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
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue2.setOwner(newOwner);
    }

    function testEnableIrmWhenNotOwner(address attacker, address newIrm) public {
        vm.assume(attacker != blue.owner());

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.enableIrm(newIrm);
    }

    function testEnableIrm(address newIrm) public {
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
        vm.assume(marketFuzz.irm != address(irm));

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

    function testFeeAccrues(uint256 assetsLent, uint256 assetsBorrowed, uint256 fee, uint256 timeElapsed) public {
        assetsLent = bound(assetsLent, 1, 2 ** 64);
        assetsBorrowed = bound(assetsBorrowed, 1, assetsLent);
        timeElapsed = bound(timeElapsed, 1, 365 days);
        fee = bound(fee, 0, MAX_FEE);
        address recipient = OWNER;

        vm.startPrank(OWNER);
        blue.setFee(market, fee);
        blue.setFeeRecipient(recipient);
        vm.stopPrank();

        borrowableAsset.setBalance(address(this), assetsLent);
        blue.supplyAssets(market, assetsLent, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrowAssets(market, assetsBorrowed, BORROWER, BORROWER);

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
        marketFuzz.irm = address(irm);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testSupplyOnBehalf(uint256 assets, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        assets = bound(assets, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), assets);
        blue.supplyAssets(market, assets, onBehalf, hex"");

        assertEq(blue.supplyShares(id, onBehalf), assets * SharesMath.VIRTUAL_SHARES, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), assets, "blue balance");
    }

    function testBorrow(uint256 assetsLent, uint256 assetsBorrowed, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        assetsLent = bound(assetsLent, 1, 2 ** 64);
        assetsBorrowed = bound(assetsBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), assetsLent);
        blue.supplyAssets(market, assetsLent, address(this), hex"");

        if (assetsBorrowed > assetsLent) {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            blue.borrowAssets(market, assetsBorrowed, BORROWER, receiver);
            return;
        }

        vm.prank(BORROWER);
        blue.borrowAssets(market, assetsBorrowed, BORROWER, receiver);

        assertEq(blue.borrowShares(id, BORROWER), assetsBorrowed * SharesMath.VIRTUAL_SHARES, "borrow share");
        assertEq(borrowableAsset.balanceOf(receiver), assetsBorrowed, "receiver balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), assetsLent - assetsBorrowed, "blue balance");
    }

    function _testWithdrawCommon(uint256 assetsLent) public {
        assetsLent = bound(assetsLent, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), assetsLent);
        blue.supplyAssets(market, assetsLent, address(this), hex"");

        // Accrue interest.
        stdstore.target(address(blue)).sig("totalSupply(bytes32)").with_key(Id.unwrap(id)).checked_write(
            blue.totalSupply(id) * 4 / 3
        );
        borrowableAsset.setBalance(address(blue), blue.totalSupply(id));
    }

    function testWithdrawShares(uint256 assetsLent, uint256 sharesWithdrawn, uint256 assetsBorrowed, address receiver)
        public
    {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        vm.assume(receiver != address(this));
        sharesWithdrawn = bound(sharesWithdrawn, 1, 2 ** 64);

        _testWithdrawCommon(assetsLent);
        assetsBorrowed = bound(assetsBorrowed, 1, blue.totalSupply(id));
        blue.borrowAssets(market, assetsBorrowed, BORROWER, BORROWER);

        uint256 totalSupplyBefore = blue.totalSupply(id);
        uint256 supplySharesBefore = blue.supplyShares(id, address(this));
        uint256 assetsWithdrawn = sharesWithdrawn.toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));

        if (sharesWithdrawn > blue.supplyShares(id, address(this))) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawShares(market, sharesWithdrawn, address(this), receiver);
            return;
        } else if (assetsWithdrawn > totalSupplyBefore - assetsBorrowed) {
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            blue.withdrawShares(market, sharesWithdrawn, address(this), receiver);
            return;
        }

        blue.withdrawShares(market, sharesWithdrawn, address(this), receiver);

        assertEq(blue.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
        assertEq(borrowableAsset.balanceOf(receiver), assetsWithdrawn, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)),
            totalSupplyBefore - assetsBorrowed - assetsWithdrawn,
            "blue balance"
        );
    }

    function testWithdrawAssets(uint256 assetsLent, uint256 exactAssetsWithdrawn) public {
        _testWithdrawCommon(assetsLent);

        uint256 totalSupplyBefore = blue.totalSupply(id);
        uint256 supplySharesBefore = blue.supplyShares(id, address(this));
        exactAssetsWithdrawn = bound(
            exactAssetsWithdrawn, 1, supplySharesBefore.toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id))
        );
        uint256 sharesWithdrawn = blue.withdrawAssets(market, exactAssetsWithdrawn, address(this), address(this));

        assertEq(blue.supplyShares(id, address(this)), supplySharesBefore - sharesWithdrawn, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), exactAssetsWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), totalSupplyBefore - exactAssetsWithdrawn, "blue balance");
    }

    function testWithdrawAll(uint256 assetsLent) public {
        _testWithdrawCommon(assetsLent);

        uint256 totalSupplyBefore = blue.totalSupply(id);
        uint256 assetsWithdrawn =
            blue.supplyShares(id, address(this)).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        blue.withdrawShares(market, blue.supplyShares(id, address(this)), address(this), address(this));

        assertEq(blue.supplyShares(id, address(this)), 0, "supply share");
        assertEq(borrowableAsset.balanceOf(address(this)), assetsWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), totalSupplyBefore - assetsWithdrawn, "blue balance");
    }

    function _testRepayCommon(uint256 assetsBorrowed, address borrower) public {
        assetsBorrowed = bound(assetsBorrowed, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), 2 ** 66);
        blue.supplyAssets(market, assetsBorrowed, address(this), hex"");
        vm.prank(borrower);
        blue.borrowAssets(market, assetsBorrowed, borrower, borrower);

        // Accrue interest.
        stdstore.target(address(blue)).sig("totalBorrow(bytes32)").with_key(Id.unwrap(id)).checked_write(
            blue.totalBorrow(id) * 4 / 3
        );
    }

    function testRepayShares(uint256 assetsBorrowed, uint256 sharesRepaid, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        _testRepayCommon(assetsBorrowed, onBehalf);

        uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
        uint256 borrowSharesBefore = blue.borrowShares(id, onBehalf);
        sharesRepaid = bound(sharesRepaid, 1, borrowSharesBefore);

        uint256 assetsRepaid = sharesRepaid.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        blue.repayShares(market, sharesRepaid, onBehalf, hex"");

        assertEq(blue.borrowShares(id, onBehalf), borrowSharesBefore - sharesRepaid, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - assetsRepaid, "this balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), assetsRepaid, "blue balance");
    }

    function testRepayAssets(uint256 assetsBorrowed, uint256 exactAssetsRepaid) public {
        _testRepayCommon(assetsBorrowed, address(this));

        uint256 thisBalanceBefore = borrowableAsset.balanceOf(address(this));
        uint256 borrowSharesBefore = blue.borrowShares(id, address(this));
        exactAssetsRepaid =
            bound(exactAssetsRepaid, 1, borrowSharesBefore.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id)));
        uint256 sharesRepaid = blue.repayAssets(market, exactAssetsRepaid, address(this), hex"");

        assertEq(blue.borrowShares(id, address(this)), borrowSharesBefore - sharesRepaid, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), thisBalanceBefore - exactAssetsRepaid, "this balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), exactAssetsRepaid, "blue balance");
    }

    function testRepayAll(uint256 assetsBorrowed) public {
        _testRepayCommon(assetsBorrowed, address(this));

        uint256 assetsRepaid =
            blue.borrowShares(id, address(this)).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        borrowableAsset.setBalance(address(this), assetsRepaid);
        blue.repayShares(market, blue.borrowShares(id, address(this)), address(this), hex"");

        assertEq(blue.borrowShares(id, address(this)), 0, "borrow share");
        assertEq(borrowableAsset.balanceOf(address(this)), 0, "this balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), assetsRepaid, "blue balance");
    }

    function testSupplyCollateralOnBehalf(uint256 assets, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(blue));
        assets = bound(assets, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), assets);
        blue.supplyCollateral(market, assets, onBehalf, hex"");

        assertEq(blue.collateral(id, onBehalf), assets, "collateral");
        assertEq(collateralAsset.balanceOf(onBehalf), 0, "onBehalf balance");
        assertEq(collateralAsset.balanceOf(address(blue)), assets, "blue balance");
    }

    function testWithdrawCollateral(uint256 assetsDeposited, uint256 assetsWithdrawn, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        assetsDeposited = bound(assetsDeposited, 1, 2 ** 64);
        assetsWithdrawn = bound(assetsWithdrawn, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), assetsDeposited);
        blue.supplyCollateral(market, assetsDeposited, address(this), hex"");

        if (assetsWithdrawn > assetsDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(market, assetsWithdrawn, address(this), receiver);
            return;
        }

        blue.withdrawCollateral(market, assetsWithdrawn, address(this), receiver);

        assertEq(blue.collateral(id, address(this)), assetsDeposited - assetsWithdrawn, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), assetsWithdrawn, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(blue)), assetsDeposited - assetsWithdrawn, "blue balance");
    }

    function testWithdrawCollateralAll(uint256 assetsDeposited, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(blue));
        assetsDeposited = bound(assetsDeposited, 1, 2 ** 64);

        collateralAsset.setBalance(address(this), assetsDeposited);
        blue.supplyCollateral(market, assetsDeposited, address(this), hex"");
        blue.withdrawCollateral(market, blue.collateral(id, address(this)), address(this), receiver);

        assertEq(blue.collateral(id, address(this)), 0, "this collateral");
        assertEq(collateralAsset.balanceOf(receiver), assetsDeposited, "receiver balance");
        assertEq(collateralAsset.balanceOf(address(blue)), 0, "blue balance");
    }

    function testCollateralRequirements(
        uint256 assetsCollateral,
        uint256 assetsBorrowed,
        uint256 priceCollateral,
        uint256 priceBorrowable
    ) public {
        assetsBorrowed = bound(assetsBorrowed, 1, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        assetsCollateral = bound(assetsCollateral, 1, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), assetsBorrowed);
        collateralAsset.setBalance(BORROWER, assetsCollateral);

        blue.supplyAssets(market, assetsBorrowed, address(this), hex"");

        vm.prank(BORROWER);
        blue.supplyCollateral(market, assetsCollateral, BORROWER, hex"");

        uint256 collateralValue = assetsCollateral.mulWadDown(priceCollateral);
        uint256 borrowValue = assetsBorrowed.mulWadUp(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.mulWadDown(LLTV))) {
            vm.prank(BORROWER);
            blue.borrowAssets(market, assetsBorrowed, BORROWER, BORROWER);
        } else {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
            blue.borrowAssets(market, assetsBorrowed, BORROWER, BORROWER);
        }
    }

    function testLiquidate(uint256 assetsLent) public {
        borrowableOracle.setPrice(1e18);
        assetsLent = bound(assetsLent, 1000, 2 ** 64);

        uint256 assetsCollateral = assetsLent;
        uint256 borrowingPower = assetsCollateral.mulWadDown(LLTV);
        uint256 assetsBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = assetsCollateral.mulWadDown(LLTV);
        uint256 incentive =
            FixedPointMathLib.WAD + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(LLTV) - FixedPointMathLib.WAD);

        borrowableAsset.setBalance(address(this), assetsLent);
        collateralAsset.setBalance(BORROWER, assetsCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, assetsBorrowed);

        // Supply
        blue.supplyAssets(market, assetsLent, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, assetsCollateral, BORROWER, hex"");
        blue.borrowAssets(market, assetsBorrowed, BORROWER, BORROWER);
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
        assertApproxEqAbs(borrowBalance(BORROWER), assetsBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(blue.collateral(id, BORROWER), assetsCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 assetsLent) public {
        borrowableOracle.setPrice(1e18);
        assetsLent = bound(assetsLent, 1000, 2 ** 64);

        uint256 assetsCollateral = assetsLent;
        uint256 borrowingPower = assetsCollateral.mulWadDown(LLTV);
        uint256 assetsBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = assetsCollateral;
        uint256 incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);

        borrowableAsset.setBalance(address(this), assetsLent);
        collateralAsset.setBalance(BORROWER, assetsCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, assetsBorrowed);

        // Supply
        blue.supplyAssets(market, assetsLent, address(this), hex"");

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, assetsCollateral, BORROWER, hex"");
        blue.borrowAssets(market, assetsBorrowed, BORROWER, BORROWER);
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
        uint256 expectedBadDebt = assetsBorrowed - expectedRepaid;
        assertGt(expectedBadDebt, 0, "bad debt");
        assertApproxEqAbs(supplyBalance(address(this)), assetsLent - expectedBadDebt, 10, "lender supply balance");
        assertApproxEqAbs(blue.totalBorrow(id), 0, 10, "total borrow");
    }

    function testTwoUsersSupply(uint256 firstAssets, uint256 secondAssets) public {
        firstAssets = bound(firstAssets, 1, 2 ** 64);
        secondAssets = bound(secondAssets, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAssets);
        blue.supplyAssets(market, firstAssets, address(this), hex"");

        borrowableAsset.setBalance(BORROWER, secondAssets);
        vm.prank(BORROWER);
        blue.supplyAssets(market, secondAssets, BORROWER, hex"");

        assertApproxEqAbs(supplyBalance(address(this)), firstAssets, 100, "same balance first user");
        assertEq(
            blue.supplyShares(id, address(this)), firstAssets * SharesMath.VIRTUAL_SHARES, "expected shares first user"
        );
        assertApproxEqAbs(supplyBalance(BORROWER), secondAssets, 100, "same balance second user");
        assertApproxEqAbs(
            blue.supplyShares(id, BORROWER),
            secondAssets * SharesMath.VIRTUAL_SHARES,
            100,
            "expected shares second user"
        );
    }

    function testUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.supplyAssets(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdrawShares(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.borrowAssets(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.repayShares(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.supplyCollateral(marketFuzz, 1, address(this), hex"");

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdrawCollateral(marketFuzz, 1, address(this), address(this));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.liquidate(marketFuzz, address(0), 1, hex"");
    }

    function testInputZero() public {
        vm.expectRevert(bytes(Errors.ZERO_ASSETS));
        blue.supplyAssets(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_SHARES));
        blue.withdrawShares(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_ASSETS));
        blue.borrowAssets(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_SHARES));
        blue.repayShares(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ASSETS));
        blue.supplyCollateral(market, 0, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ASSETS));
        blue.withdrawCollateral(market, 0, address(this), address(this));

        vm.expectRevert(bytes(Errors.ZERO_ASSETS));
        blue.liquidate(market, address(0), 0, hex"");
    }

    function testZeroAddress() public {
        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.supplyAssets(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdrawShares(market, 1, address(this), address(0));

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.borrowAssets(market, 1, address(this), address(0));

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.repayShares(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.supplyCollateral(market, 1, address(0), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdrawCollateral(market, 1, address(this), address(0));
    }

    function testEmptyMarket(uint256 assets) public {
        assets = bound(assets, 1, type(uint256).max / SharesMath.VIRTUAL_SHARES);

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawShares(market, assets, address(this), address(this));

        vm.expectRevert(stdError.arithmeticError);
        blue.repayShares(market, assets, address(this), hex"");

        vm.expectRevert(stdError.arithmeticError);
        blue.withdrawCollateral(market, assets, address(this), address(this));
    }

    function testSetAuthorization(address authorized, bool isAuthorized) public {
        blue.setAuthorization(authorized, isAuthorized);
        assertEq(blue.isAuthorized(address(this), authorized), isAuthorized);
    }

    function testNotAuthorized(address attacker) public {
        vm.assume(attacker != address(this));

        vm.startPrank(attacker);

        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdrawShares(market, 1, address(this), address(this));
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdrawCollateral(market, 1, address(this), address(this));
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.borrowAssets(market, 1, address(this), address(this));

        vm.stopPrank();
    }

    function testAuthorization(address authorized) public {
        borrowableAsset.setBalance(address(this), 100 ether);
        collateralAsset.setBalance(address(this), 100 ether);

        blue.supplyAssets(market, 100 ether, address(this), hex"");
        blue.supplyCollateral(market, 100 ether, address(this), hex"");

        blue.setAuthorization(authorized, true);

        vm.startPrank(authorized);

        blue.withdrawShares(market, 1 ether, address(this), address(this));
        blue.withdrawCollateral(market, 1 ether, address(this), address(this));
        blue.borrowAssets(market, 1 ether, address(this), address(this));

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

        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );

        assertEq(blue.isAuthorized(authorizer, authorized), isAuthorized);
        assertEq(blue.nonce(authorizer), 1);
    }

    function testFlashLoan(uint256 assets) public {
        assets = bound(assets, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), assets);
        blue.supplyAssets(market, assets, address(this), hex"");

        blue.flashLoan(address(borrowableAsset), assets, bytes(""));

        assertEq(borrowableAsset.balanceOf(address(blue)), assets, "balanceOf");
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

    function testSupplyCallback(uint256 assets) public {
        assets = bound(assets, 1, 2 ** 64);
        borrowableAsset.setBalance(address(this), assets);
        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supplyAssets(market, assets, address(this), hex"");
        blue.supplyAssets(market, assets, address(this), abi.encode(this.testSupplyCallback.selector, hex""));
    }

    function testSupplyCollateralCallback(uint256 assets) public {
        assets = bound(assets, 1, 2 ** 64);
        collateralAsset.setBalance(address(this), assets);
        collateralAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.supplyCollateral(market, assets, address(this), hex"");
        blue.supplyCollateral(
            market, assets, address(this), abi.encode(this.testSupplyCollateralCallback.selector, hex"")
        );
    }

    function testRepayCallback(uint256 assets) public {
        assets = bound(assets, 1, 2 ** 64);
        borrowableAsset.setBalance(address(this), assets);
        blue.supplyAssets(market, assets, address(this), hex"");
        blue.borrowAssets(market, assets, address(this), address(this));

        borrowableAsset.approve(address(blue), 0);

        vm.expectRevert();
        blue.repayShares(market, assets, address(this), hex"");
        blue.repayShares(market, assets, address(this), abi.encode(this.testRepayCallback.selector, hex""));
    }

    function testLiquidateCallback(uint256 assets) public {
        assets = bound(assets, 10, 2 ** 64);
        borrowableOracle.setPrice(1e18);
        borrowableAsset.setBalance(address(this), assets);
        collateralAsset.setBalance(address(this), assets);
        blue.supplyAssets(market, assets, address(this), hex"");
        blue.supplyCollateral(market, assets, address(this), hex"");
        blue.borrowAssets(market, assets.mulWadDown(LLTV), address(this), address(this));

        borrowableOracle.setPrice(1.01e18);

        uint256 toSeize = assets.mulWadDown(LLTV);

        borrowableAsset.setBalance(address(this), toSeize);
        borrowableAsset.approve(address(blue), 0);
        vm.expectRevert();
        blue.liquidate(market, address(this), toSeize, hex"");
        blue.liquidate(market, address(this), toSeize, abi.encode(this.testLiquidateCallback.selector, hex""));
    }

    function testFlashActions(uint256 assets) public {
        assets = bound(assets, 10, 2 ** 64);
        borrowableOracle.setPrice(1e18);
        uint256 toBorrow = assets.mulWadDown(LLTV);

        borrowableAsset.setBalance(address(this), 2 * toBorrow);
        blue.supplyAssets(market, toBorrow, address(this), hex"");

        blue.supplyCollateral(
            market, assets, address(this), abi.encode(this.testFlashActions.selector, abi.encode(toBorrow))
        );
        assertGt(blue.borrowShares(market.id(), address(this)), 0, "no borrow");

        blue.repayShares(
            market,
            blue.borrowShares(id, address(this)),
            address(this),
            abi.encode(this.testFlashActions.selector, abi.encode(assets))
        );
        assertEq(blue.collateral(market.id(), address(this)), 0, "no withdraw collateral");
    }

    // Callback functions.

    function onBlueSupply(uint256 assets, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCallback.selector) {
            borrowableAsset.approve(address(blue), assets);
        }
    }

    function onBlueSupplyCollateral(uint256 assets, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testSupplyCollateralCallback.selector) {
            collateralAsset.approve(address(blue), assets);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toBorrow = abi.decode(data, (uint256));
            collateralAsset.setBalance(address(this), assets);
            borrowableAsset.setBalance(address(this), toBorrow);
            blue.borrowAssets(market, toBorrow, address(this), address(this));
        }
    }

    function onBlueRepay(uint256 assets, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testRepayCallback.selector) {
            borrowableAsset.approve(address(blue), assets);
        } else if (selector == this.testFlashActions.selector) {
            uint256 toWithdraw = abi.decode(data, (uint256));
            blue.withdrawCollateral(market, toWithdraw, address(this), address(this));
        }
    }

    function onBlueLiquidate(uint256, uint256 repaid, bytes memory data) external {
        require(msg.sender == address(blue));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.testLiquidateCallback.selector) {
            borrowableAsset.approve(address(blue), repaid);
        }
    }

    function onBlueFlashLoan(address token, uint256 assets, bytes calldata) external {
        ERC20(token).approve(address(blue), assets);
    }
}

function neq(Market memory a, Market memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lltv != b.lltv
        || a.irm != b.irm;
}
