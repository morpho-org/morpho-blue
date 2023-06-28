// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";

contract BlueTest is Test {
    using MathLib for uint;

    address private constant borrower = address(1234);
    uint private constant lLTV = 0.8 ether;

    Blue private blue;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private borrowableOracle;
    Oracle private collateralOracle;
    Info public info;
    Id public id;

    function setUp() public {
        // Create Blue.
        blue = new Blue();

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();
        info = Info(
            IERC20(address(borrowableAsset)), IERC20(address(collateralAsset)), borrowableOracle, collateralOracle, lLTV
        );
        id = Id.wrap(keccak256(abi.encode(info)));

        blue.createMarket(info);

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
    }

    function invariantLiquidity() public {
        assertLe(blue.totalBorrow(id), blue.totalSupply(id));
    }

    function testDeposit(uint amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.modifyDeposit(info, int(amount));

        assertEq(blue.supplyShare(id, address(this)), 1e18);
        assertEq(borrowableAsset.balanceOf(address(this)), 0);
        assertEq(borrowableAsset.balanceOf(address(blue)), amount);
    }

    function testBorrow(uint amountLent, uint amountBorrowed) public {
        amountLent = bound(amountLent, 0, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 0, 2 ** 64);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.modifyDeposit(info, int(amountLent));

        if (amountBorrowed == 0) {
            blue.modifyBorrow(info, int(amountBorrowed));
            return;
        }

        if (amountBorrowed > amountLent) {
            vm.prank(borrower);
            vm.expectRevert("not enough liquidity");
            blue.modifyBorrow(info, int(amountBorrowed));
            return;
        }

        vm.prank(borrower);
        blue.modifyBorrow(info, int(amountBorrowed));

        assertEq(blue.borrowShare(id, borrower), 1e18);
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed);
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed);
    }

    function testWithdraw(uint amountLent, uint amountWithdrawn, uint amountBorrowed) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        vm.assume(amountLent >= amountBorrowed);
        vm.assume(int(amountWithdrawn) >= 0);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.modifyDeposit(info, int(amountLent));

        vm.prank(borrower);
        blue.modifyBorrow(info, int(amountBorrowed));

        if (amountWithdrawn > amountLent - amountBorrowed) {
            if (amountWithdrawn > amountLent) {
                vm.expectRevert();
            } else {
                vm.expectRevert("not enough liquidity");
            }
            blue.modifyDeposit(info, -int(amountWithdrawn));
            return;
        }

        blue.modifyDeposit(info, -int(amountWithdrawn));

        assertApproxEqAbs(
            blue.supplyShare(id, address(this)), ((amountLent - amountWithdrawn) * 1e18) / amountLent, 1e3
        );
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn);
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed - amountWithdrawn);
    }

    function testCollateralRequirements(
        uint amountCollateral,
        uint amountBorrowed,
        uint priceCollateral,
        uint priceBorrowable
    ) public {
        amountBorrowed = bound(amountBorrowed, 0, 2 ** 64);
        priceBorrowable = bound(priceBorrowable, 0, 2 ** 64);
        amountCollateral = bound(amountCollateral, 0, 2 ** 64);
        priceCollateral = bound(priceCollateral, 0, 2 ** 64);

        borrowableOracle.setPrice(priceBorrowable);
        collateralOracle.setPrice(priceCollateral);

        borrowableAsset.setBalance(address(this), amountBorrowed);
        collateralAsset.setBalance(borrower, amountCollateral);

        blue.modifyDeposit(info, int(amountBorrowed));

        vm.prank(borrower);
        blue.modifyCollateral(info, int(amountCollateral));

        uint collateralValue = amountCollateral.wMul(priceCollateral);
        uint borrowValue = amountBorrowed.wMul(priceBorrowable);
        if (borrowValue == 0 || (collateralValue > 0 && borrowValue <= collateralValue.wMul(lLTV))) {
            vm.prank(borrower);
            blue.modifyBorrow(info, int(amountBorrowed));
        } else {
            vm.prank(borrower);
            vm.expectRevert("not enough collateral");
            blue.modifyBorrow(info, int(amountBorrowed));
        }
    }

    function testRepay(uint amountLent, uint amountBorrowed, uint amountRepaid) public {
        amountLent = bound(amountLent, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountLent);
        amountRepaid = bound(amountRepaid, 0, amountBorrowed);

        borrowableAsset.setBalance(address(this), amountLent);
        blue.modifyDeposit(info, int(amountLent));

        vm.startPrank(borrower);
        blue.modifyBorrow(info, int(amountBorrowed));
        blue.modifyBorrow(info, -int(amountRepaid));
        vm.stopPrank();

        assertApproxEqAbs(
            blue.borrowShare(id, borrower), ((amountBorrowed - amountRepaid) * 1e18) / amountBorrowed, 1e3
        );
        assertEq(borrowableAsset.balanceOf(borrower), amountBorrowed - amountRepaid);
        assertEq(borrowableAsset.balanceOf(address(blue)), amountLent - amountBorrowed + amountRepaid);
    }

    function testDepositCollateral(uint amount) public {
        vm.assume(int(amount) >= 0);

        collateralAsset.setBalance(address(this), amount);
        blue.modifyCollateral(info, int(amount));

        assertEq(blue.collateral(id, address(this)), amount);
        assertEq(collateralAsset.balanceOf(address(this)), 0);
        assertEq(collateralAsset.balanceOf(address(blue)), amount);
    }

    function testWithdrawCollateral(uint amountDeposited, uint amountWithdrawn) public {
        vm.assume(int(amountDeposited) > 0);
        vm.assume(int(amountWithdrawn) > 0);

        collateralAsset.setBalance(address(this), amountDeposited);
        blue.modifyCollateral(info, int(amountDeposited));

        if (amountWithdrawn > amountDeposited) {
            vm.expectRevert("negative");
            blue.modifyCollateral(info, -int(amountWithdrawn));
            return;
        }

        blue.modifyCollateral(info, -int(amountWithdrawn));

        assertEq(blue.collateral(id, address(this)), amountDeposited - amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(this)), amountWithdrawn);
        assertEq(collateralAsset.balanceOf(address(blue)), amountDeposited - amountWithdrawn);
    }

    function testTwoUsersSupply(uint firstAmount, uint secondAmount) public {
        firstAmount = bound(firstAmount, 1, 2 ** 64);
        secondAmount = bound(secondAmount, 0, 2 ** 64);

        borrowableAsset.setBalance(address(this), firstAmount);
        blue.modifyDeposit(info, int(firstAmount));

        borrowableAsset.setBalance(borrower, secondAmount);
        vm.prank(borrower);
        blue.modifyDeposit(info, int(secondAmount));

        assertEq(blue.supplyShare(id, address(this)), 1e18);
        assertEq(blue.supplyShare(id, borrower), (secondAmount * 1e18) / firstAmount);
    }

    function testModifyDepositUnknownMarket(Info memory infoFuzz) public {
        vm.assume(neq(infoFuzz, info));
        vm.expectRevert("unknown market");
        blue.modifyDeposit(infoFuzz, 1);
    }

    function testModifyBorrowUnknownMarket(Info memory infoFuzz) public {
        vm.assume(neq(infoFuzz, info));
        vm.expectRevert("unknown market");
        blue.modifyBorrow(infoFuzz, 1);
    }

    function testModifyCollateralUnknownMarket(Info memory infoFuzz) public {
        vm.assume(neq(infoFuzz, info));
        vm.expectRevert("unknown market");
        blue.modifyCollateral(infoFuzz, 1);
    }

    function testWithdrawEmptyMarket(int amount) public {
        vm.assume(amount < 0);
        vm.expectRevert(stdError.divisionError);
        blue.modifyDeposit(info, amount);
    }

    function testRepayEmptyMarket(int amount) public {
        vm.assume(amount < 0);
        vm.expectRevert(stdError.divisionError);
        blue.modifyBorrow(info, amount);
    }

    function testWithdrawCollateralEmptyMarket(int amount) public {
        vm.assume(amount < 0);
        vm.expectRevert("negative");
        blue.modifyCollateral(info, amount);
    }
}

function neq(Info memory a, Info memory b) pure returns (bool) {
    return a.borrowableAsset != b.borrowableAsset || a.collateralAsset != b.collateralAsset
        || a.borrowableOracle != b.borrowableOracle || a.collateralOracle != b.collateralOracle || a.lLTV != b.lLTV;
}
