// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract BlueTest is Test {
    using FixedPointMathLib for uint256;

    address private constant BORROWER = address(1234);
    address private constant LIQUIDATOR = address(5678);
    uint256 private constant LLTV = 0.8 ether;
    address private constant OWNER = address(0xdead);
    address private constant NATIVE_SUPPLIER = address(1111);

    Blue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    Irm private irm;
    Market public market;
    Market public nativeBorrowableMarket;
    Market public nativeCollateralMarket;
    Id public id;
    Id public nativeBorrowableId;
    Id public nativeCollateralId;

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

    function createNativeBorrowableMarket() internal view returns (Market memory) {
        return
            Market(IERC20(address(0)), IERC20(address(collateralAsset)), borrowableOracle, collateralOracle, irm, LLTV);
    }

    function createNativeCollateralMarket() internal view returns (Market memory) {
        return
            Market(IERC20(address(borrowableAsset)), IERC20(address(0)), borrowableOracle, collateralOracle, irm, LLTV);
    }

    // To move to a test utils file later.

    function netWorth(address user) internal view returns (uint256) {
        uint256 collateralAssetValue = collateralAsset.balanceOf(user).mulWadDown(collateralOracle.price());
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user).mulWadDown(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function nativeBorrowableNetWorth(address user) internal view returns (uint256) {
        uint256 collateralAssetValue = collateralAsset.balanceOf(user).mulWadDown(collateralOracle.price());
        uint256 borrowableAssetValue = user.balance.mulWadDown(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function nativeCollateralNetWorth(address user) internal view returns (uint256) {
        uint256 collateralAssetValue = user.balance.mulWadDown(collateralOracle.price());
        uint256 borrowableAssetValue = borrowableAsset.balanceOf(user).mulWadDown(borrowableOracle.price());
        return collateralAssetValue + borrowableAssetValue;
    }

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = blue.supplyShare(id, user);
        if (supplyShares == 0) return 0;

        uint256 totalShares = blue.totalSupplyShares(id);
        uint256 totalSupply = blue.totalSupply(id);
        return supplyShares.divWadDown(totalShares).mulWadDown(totalSupply);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShare(id, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = blue.totalBorrowShares(id);
        uint256 totalBorrow = blue.totalBorrow(id);
        return borrowerShares.divWadUp(totalShares).mulWadUp(totalBorrow);
    }

    function borrowBalanceNativeBorrowable(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShare(nativeBorrowableId, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = blue.totalBorrowShares(nativeBorrowableId);
        uint256 totalBorrow = blue.totalBorrow(nativeBorrowableId);
        return borrowerShares.divWadUp(totalShares).mulWadUp(totalBorrow);
    }

    function borrowBalanceNativeCollateral(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShare(nativeCollateralId, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = blue.totalBorrowShares(nativeCollateralId);
        uint256 totalBorrow = blue.totalBorrow(nativeCollateralId);
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
        blue2.transferOwnership(newOwner);
        assertEq(blue2.owner(), newOwner, "owner");
    }

    function testTransferOwnershipWhenNotOwner(address attacker, address newOwner) public {
        vm.assume(attacker != OWNER);

        Blue blue2 = new Blue(OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue2.transferOwnership(newOwner);
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

    function testCreateMarketWithNativeBorrowable() public {
        nativeBorrowableMarket = createNativeBorrowableMarket();
        blue.createMarket(nativeBorrowableMarket);
        nativeBorrowableId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));
    }

    function testCreateMarketWithNativeCollateral() public {
        nativeCollateralMarket = createNativeCollateralMarket();
        blue.createMarket(nativeCollateralMarket);
        nativeCollateralId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));
    }

    function testEnableLltvWhenNotOwner(address attacker, uint256 newLltv) public {
        vm.assume(attacker != OWNER);

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
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
        vm.expectRevert(bytes(Errors.LLTV_TOO_HIGH));
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
        uint256 expectedFee = accrued.mulWadDown(fee);
        uint256 expectedFeeShares = expectedFee.mulDivDown(totalSupplySharesBefore, totalSupplyAfter - expectedFee);

        assertEq(blue.supplyShare(id, recipient), expectedFeeShares);
    }

    function testCreateMarketWithNotEnabledLltv(Market memory marketFuzz) public {
        vm.assume(marketFuzz.lltv != LLTV);
        marketFuzz.irm = irm;

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_NOT_ENABLED));
        blue.createMarket(marketFuzz);
    }

    function testSupplyOnBehalf(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, onBehalf);

        assertEq(blue.supplyShare(id, onBehalf), amount * SharesMath.VIRTUAL_SHARES, "supply share");
        assertEq(borrowableAsset.balanceOf(onBehalf), 0, "lender balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amount, "blue balance");
    }

    function testSupplyNativeTokenOnBehalf(uint256 amount, address onBehalf) public {
        nativeBorrowableMarket = createNativeBorrowableMarket();
        blue.createMarket(nativeBorrowableMarket);
        nativeBorrowableId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));

        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        vm.deal(address(this), 2 * amount);

        uint256 thisNativeBalanceBefore = address(this).balance;
        uint256 blueNativeBalanceBefore = address(blue).balance;
        blue.supply{value: amount}(nativeBorrowableMarket, amount, onBehalf);
        uint256 thisNativeBalanceAfter = address(this).balance;
        uint256 blueNativeBalanceAfter = address(blue).balance;

        assertEq(thisNativeBalanceBefore, thisNativeBalanceAfter + amount, "contract native balance");
        assertEq(blueNativeBalanceBefore + amount, blueNativeBalanceAfter, "blue native balance");
        assertEq(blue.supplyShare(nativeBorrowableId, onBehalf), amount * SharesMath.VIRTUAL_SHARES, "supply share");
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
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            blue.borrow(market, amountBorrowed, BORROWER);
            return;
        }

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER);

        assertEq(blue.borrowShare(id, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow share");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed, "blue balance");
    }

    function testBorrowNativeToken(uint256 amountLent, uint256 amountBorrowed) public {
        nativeBorrowableMarket = createNativeBorrowableMarket();
        blue.createMarket(nativeBorrowableMarket);
        nativeBorrowableId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));

        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);

        vm.deal(address(this), 2 * amountLent);

        uint256 blueNativeBalanceBefore = address(blue).balance;

        blue.supply{value: amountLent}(nativeBorrowableMarket, amountLent, address(this));

        if (amountBorrowed == 0) {
            blue.borrow(nativeBorrowableMarket, amountBorrowed, address(this));
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            blue.borrow(nativeBorrowableMarket, amountBorrowed, BORROWER);
            return;
        }

        uint256 borrowerNativeBalanceBefore = BORROWER.balance;

        vm.prank(BORROWER);
        blue.borrow(nativeBorrowableMarket, amountBorrowed, BORROWER);

        uint256 borrowerNativeBalanceAfter = BORROWER.balance;
        uint256 blueNativeBalanceAfter = address(blue).balance;

        assertEq(
            blue.borrowShare(nativeBorrowableId, BORROWER), amountBorrowed * SharesMath.VIRTUAL_SHARES, "borrow share"
        );
        assertEq(borrowerNativeBalanceBefore + amountBorrowed, borrowerNativeBalanceAfter, "BORROWER balance");
        assertEq(blueNativeBalanceAfter, blueNativeBalanceBefore + amountLent - amountBorrowed, "blue native balance");
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
                vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            }
            blue.withdraw(market, amountWithdrawn, address(this));
            return;
        }

        blue.withdraw(market, amountWithdrawn, address(this));

        assertApproxEqAbs(
            blue.supplyShare(id, address(this)),
            (amountLent - amountWithdrawn) * SharesMath.VIRTUAL_SHARES,
            100,
            "supply share"
        );
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed - amountWithdrawn, "blue balance"
        );
    }

    struct NativeWithdrawTestParams {
        uint256 blueNativeBalanceBefore;
        uint256 blueNativeBalanceAfter;
        uint256 nativeSupplierBalanceBefore;
        uint256 nativeSupplierBalanceAfter;
    }

    function testWithdrawNativeToken(uint256 amountLent, uint256 amountWithdrawn, uint256 amountBorrowed) public {
        NativeWithdrawTestParams memory params;

        nativeBorrowableMarket = createNativeBorrowableMarket();
        blue.createMarket(nativeBorrowableMarket);
        nativeBorrowableId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));

        amountLent = bound(amountLent, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);

        params.blueNativeBalanceBefore = address(blue).balance;

        vm.deal(NATIVE_SUPPLIER, 2 * amountLent);
        vm.prank(NATIVE_SUPPLIER);
        blue.supply{value: amountLent}(nativeBorrowableMarket, amountLent, NATIVE_SUPPLIER);

        vm.prank(BORROWER);
        blue.borrow(nativeBorrowableMarket, amountBorrowed, BORROWER);

        params.nativeSupplierBalanceBefore = NATIVE_SUPPLIER.balance;

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
            }
            vm.prank(NATIVE_SUPPLIER);
            blue.withdraw(nativeBorrowableMarket, amountWithdrawn, NATIVE_SUPPLIER);
            return;
        }

        vm.prank(NATIVE_SUPPLIER);
        blue.withdraw(nativeBorrowableMarket, amountWithdrawn, NATIVE_SUPPLIER);

        params.nativeSupplierBalanceAfter = NATIVE_SUPPLIER.balance;
        params.blueNativeBalanceAfter = address(blue).balance;

        assertApproxEqAbs(
            blue.supplyShare(nativeBorrowableId, NATIVE_SUPPLIER),
            (amountLent - amountWithdrawn) * SharesMath.VIRTUAL_SHARES,
            100,
            "supply share"
        );
        assertEq(
            params.nativeSupplierBalanceBefore + amountWithdrawn,
            params.nativeSupplierBalanceAfter,
            "native supplier balance"
        );
        assertEq(
            params.blueNativeBalanceBefore + amountLent - amountBorrowed - amountWithdrawn,
            params.blueNativeBalanceAfter,
            "blue balance"
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

        uint256 collateralValue = amountCollateral.mulWadDown(priceCollateral);
        uint256 borrowValue = amountBorrowed.mulWadUp(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.mulWadDown(LLTV))) {
            vm.prank(BORROWER);
            blue.borrow(market, amountBorrowed, BORROWER);
        } else {
            vm.prank(BORROWER);
            vm.expectRevert(bytes(Errors.INSUFFICIENT_COLLATERAL));
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
            blue.borrowShare(id, BORROWER),
            (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES,
            100,
            "borrow share"
        );
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed - amountRepaid, "BORROWER balance");
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid, "blue balance");
    }

    struct NativeRepayTestParams {
        uint256 blueNativeBalanceBefore;
        uint256 blueNativeBalanceAfter;
        uint256 borrowerNativeBalanceBefore;
        uint256 borrowerNativeBalanceAfter;
    }

    function testRepayNativeToken(uint256 amountLent, uint256 amountBorrowed, uint256 amountRepaid) public {
        NativeRepayTestParams memory params;

        nativeBorrowableMarket = createNativeBorrowableMarket();
        blue.createMarket(nativeBorrowableMarket);
        nativeBorrowableId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));

        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        vm.deal(address(this), 2 * amountLent);
        params.blueNativeBalanceBefore = address(blue).balance;
        blue.supply{value: amountLent}(nativeBorrowableMarket, amountLent, address(this));

        params.borrowerNativeBalanceBefore = BORROWER.balance;

        vm.startPrank(BORROWER);
        blue.borrow(nativeBorrowableMarket, amountBorrowed, BORROWER);
        blue.repay{value: amountRepaid}(nativeBorrowableMarket, amountRepaid, BORROWER);
        vm.stopPrank();

        params.blueNativeBalanceAfter = address(blue).balance;
        params.borrowerNativeBalanceAfter = BORROWER.balance;

        assertApproxEqAbs(
            blue.borrowShare(nativeBorrowableId, BORROWER),
            (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES,
            100,
            "borrow share"
        );
        assertEq(
            params.borrowerNativeBalanceBefore + amountBorrowed - amountRepaid,
            params.borrowerNativeBalanceAfter,
            "BORROWER balance"
        );
        assertEq(
            params.blueNativeBalanceBefore + amountLent - amountBorrowed + amountRepaid,
            params.blueNativeBalanceAfter,
            "blue balance"
        );
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
            blue.borrowShare(id, onBehalf),
            (amountBorrowed - amountRepaid) * SharesMath.VIRTUAL_SHARES,
            100,
            "borrow share"
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

    function testSupplyNativeCollateralOnBehalf(uint256 amount, address onBehalf) public {
        nativeCollateralMarket = createNativeCollateralMarket();
        blue.createMarket(nativeCollateralMarket);
        nativeCollateralId = Id.wrap(keccak256(abi.encode(nativeCollateralMarket)));

        vm.assume(onBehalf != address(blue));
        amount = bound(amount, 1, 2 ** 64);

        vm.deal(address(this), 2 * amount);
        uint256 thisNativeBalanceBefore = address(this).balance;
        uint256 blueNativeBalanceBefore = address(blue).balance;
        blue.supplyCollateral{value: amount}(nativeCollateralMarket, amount, onBehalf);
        uint256 thisNativeBalanceAfter = address(this).balance;
        uint256 blueNativeBalanceAfter = address(blue).balance;

        assertEq(blue.collateral(nativeCollateralId, onBehalf), amount, "collateral");
        assertEq(thisNativeBalanceBefore, thisNativeBalanceAfter + amount, "this balance");
        assertEq(blueNativeBalanceBefore + amount, blueNativeBalanceAfter, "blue balance");
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

    function testWithdrawNativeCollateral(uint256 amountDeposited, uint256 amountWithdrawn) public {
        nativeCollateralMarket = createNativeCollateralMarket();
        blue.createMarket(nativeCollateralMarket);
        nativeCollateralId = Id.wrap(keccak256(abi.encode(nativeCollateralMarket)));

        amountDeposited = bound(amountDeposited, 1, 2 ** 64);
        amountWithdrawn = bound(amountWithdrawn, 1, 2 ** 64);

        vm.deal(NATIVE_SUPPLIER, 2 * amountDeposited);
        vm.startPrank(NATIVE_SUPPLIER);

        uint256 blueNativeBalanceBefore = address(blue).balance;
        blue.supplyCollateral{value: amountDeposited}(nativeCollateralMarket, amountDeposited, NATIVE_SUPPLIER);
        uint256 nativeSupplierBalanceBefore = NATIVE_SUPPLIER.balance;

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert(stdError.arithmeticError);
            blue.withdrawCollateral(nativeCollateralMarket, amountWithdrawn, NATIVE_SUPPLIER);
            return;
        }

        blue.withdrawCollateral(nativeCollateralMarket, amountWithdrawn, NATIVE_SUPPLIER);

        vm.stopPrank();
        uint256 nativeSupplierBalanceAfter = NATIVE_SUPPLIER.balance;
        uint256 blueNativeBalanceAfter = address(blue).balance;

        if (amountDeposited > amountWithdrawn) {
            assertEq(
                blue.collateral(nativeCollateralId, NATIVE_SUPPLIER),
                amountDeposited - amountWithdrawn,
                "this collateral"
            );
            assertEq(nativeSupplierBalanceBefore + amountWithdrawn, nativeSupplierBalanceAfter, "this balance");
            assertEq(
                blueNativeBalanceBefore + amountDeposited - amountWithdrawn, blueNativeBalanceAfter, "blue balance"
            );
        }
    }

    function testLiquidate(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.mulWadDown(LLTV);
        uint256 amountBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = amountCollateral.mulWadDown(LLTV);
        uint256 incentive = WAD + ALPHA.mulWadDown(WAD.divWadDown(LLTV) - WAD);

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

        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());
        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(borrowBalance(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance");
        assertEq(blue.collateral(id, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testLiquidateBorrowNativeBorrowable(uint256 amountLent) public {
        nativeBorrowableMarket = createNativeBorrowableMarket();
        blue.createMarket(nativeBorrowableMarket);
        nativeBorrowableId = Id.wrap(keccak256(abi.encode(nativeBorrowableMarket)));

        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.mulWadDown(LLTV);
        uint256 amountBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = amountCollateral.mulWadDown(LLTV);
        uint256 incentive = WAD + ALPHA.mulWadDown(WAD.divWadDown(LLTV) - WAD);

        vm.deal(address(this), 2 * amountLent);
        collateralAsset.setBalance(BORROWER, amountCollateral);
        vm.deal(LIQUIDATOR, 2 * amountBorrowed);

        // Supply
        blue.supply{value: amountLent}(nativeBorrowableMarket, amountLent, address(this));

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral(nativeBorrowableMarket, amountCollateral, BORROWER);
        blue.borrow(nativeBorrowableMarket, amountBorrowed, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint256 liquidatorNetWorthBefore = nativeBorrowableNetWorth(LIQUIDATOR);

        // Liquidate
        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());

        vm.prank(LIQUIDATOR);
        blue.liquidate{value: expectedRepaid + 1}(nativeBorrowableMarket, BORROWER, toSeize);

        uint256 liquidatorNetWorthAfter = nativeBorrowableNetWorth(LIQUIDATOR);

        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(
            borrowBalanceNativeBorrowable(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance"
        );
        assertEq(blue.collateral(nativeBorrowableId, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testLiquidateBorrowNativeCollateral(uint256 amountLent) public {
        nativeCollateralMarket = createNativeCollateralMarket();
        blue.createMarket(nativeCollateralMarket);
        nativeCollateralId = Id.wrap(keccak256(abi.encode(nativeCollateralMarket)));

        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.mulWadDown(LLTV);
        uint256 amountBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = amountCollateral.mulWadDown(LLTV);
        uint256 incentive = WAD + ALPHA.mulWadDown(WAD.divWadDown(LLTV) - WAD);

        borrowableAsset.setBalance(address(this), amountLent);
        vm.deal(BORROWER, 2 * amountCollateral);
        borrowableAsset.setBalance(LIQUIDATOR, amountBorrowed);

        // Supply
        blue.supply(nativeCollateralMarket, amountLent, address(this));

        // Borrow
        vm.startPrank(BORROWER);
        blue.supplyCollateral{value: amountCollateral}(nativeCollateralMarket, amountCollateral, BORROWER);
        blue.borrow(nativeCollateralMarket, amountBorrowed, BORROWER);
        vm.stopPrank();

        // Price change
        borrowableOracle.setPrice(2e18);

        uint256 liquidatorNetWorthBefore = nativeCollateralNetWorth(LIQUIDATOR);

        // Liquidate
        uint256 expectedRepaid =
            toSeize.mulWadUp(collateralOracle.price()).divWadUp(incentive).divWadUp(borrowableOracle.price());

        vm.prank(LIQUIDATOR);
        blue.liquidate(nativeCollateralMarket, BORROWER, toSeize);

        uint256 liquidatorNetWorthAfter = nativeCollateralNetWorth(LIQUIDATOR);

        uint256 expectedNetWorthAfter = liquidatorNetWorthBefore + toSeize.mulWadDown(collateralOracle.price())
            - expectedRepaid.mulWadDown(borrowableOracle.price());
        assertEq(liquidatorNetWorthAfter, expectedNetWorthAfter, "LIQUIDATOR net worth");
        assertApproxEqAbs(
            borrowBalanceNativeCollateral(BORROWER), amountBorrowed - expectedRepaid, 100, "BORROWER balance"
        );
        assertEq(blue.collateral(nativeCollateralId, BORROWER), amountCollateral - toSeize, "BORROWER collateral");
    }

    function testRealizeBadDebt(uint256 amountLent) public {
        borrowableOracle.setPrice(1e18);
        amountLent = bound(amountLent, 1000, 2 ** 64);

        uint256 amountCollateral = amountLent;
        uint256 borrowingPower = amountCollateral.mulWadDown(LLTV);
        uint256 amountBorrowed = borrowingPower.mulWadDown(0.8e18);
        uint256 toSeize = amountCollateral;
        uint256 incentive = WAD + ALPHA.mulWadDown(WAD.divWadDown(market.lltv) - WAD);

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
        blue.supply(market, firstAmount, address(this));

        borrowableAsset.setBalance(BORROWER, secondAmount);
        vm.prank(BORROWER);
        blue.supply(market, secondAmount, BORROWER);

        assertApproxEqAbs(supplyBalance(address(this)), firstAmount, 100, "same balance first user");
        assertEq(
            blue.supplyShare(id, address(this)), firstAmount * SharesMath.VIRTUAL_SHARES, "expected shares first user"
        );
        assertApproxEqAbs(supplyBalance(BORROWER), secondAmount, 100, "same balance second user");
        assertApproxEqAbs(
            blue.supplyShare(id, BORROWER), secondAmount * SharesMath.VIRTUAL_SHARES, 100, "expected shares second user"
        );
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
        amount = bound(amount, 1, type(uint256).max / SharesMath.VIRTUAL_SHARES);

        vm.expectRevert(stdError.arithmeticError);
        blue.withdraw(market, amount, address(this));

        vm.expectRevert(stdError.arithmeticError);
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
