// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationWithdrawTest is BaseTest {
    using FixedPointMathLib for uint256;

    function testWithdrawMarketNotCreated(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        blue.withdraw(marketFuzz, 1, 0, address(this), address(this));
    }

    function testWithdrawZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.withdraw(market, 0, 0, address(this), address(this));
    }

    function testWithdrawInconsistantInput(uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        blue.withdraw(market, amount, shares, address(this), address(this));
    }

    function testWithdrawToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        blue.withdraw(market, amount, 0, address(this), address(0));
    }

    function testWithdrawUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, 0, address(this), hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        blue.withdraw(market, amount, 0, address(this), address(this));
    }

    function testWithdrawInsufficientLiquidity(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        address supplier,
        address borrowerFuzz,
        address receiver
    ) public {
        vm.assume(supplier != address(0) && supplier != address(blue));
        vm.assume(borrowerFuzz != address(0) && borrowerFuzz != address(blue));
        vm.assume(receiver != address(0));

        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountSupplied = bound(amountSupplied, amountBorrowed + 1, MAX_TEST_AMOUNT + 1);

        borrowableAsset.setBalance(supplier, amountSupplied);

        vm.startPrank(supplier);
        borrowableAsset.approve(address(blue), amountSupplied);
        blue.supply(market, amountSupplied, 0, supplier, hex"");
        vm.stopPrank();

        uint256 amountCollateral = amountBorrowed.wDivUp(LLTV);
        collateralAsset.setBalance(borrowerFuzz, amountCollateral);

        vm.startPrank(borrowerFuzz);
        collateralAsset.approve(address(blue), amountCollateral);
        blue.supplyCollateral(market, amountCollateral, borrowerFuzz, hex"");
        blue.borrow(market, amountBorrowed, 0, borrowerFuzz, receiver);
        vm.stopPrank();

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
        blue.withdraw(market, amountSupplied, 0, supplier, receiver);
    }

    function testWithdrawAmount(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountWithdrawn,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(blue));
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV));
        blue.supply(market, amountSupplied, 0, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), BORROWER, hex"");
        blue.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.Withdraw(
            id, address(this), address(this), receiver, amountWithdrawn, amountWithdrawn * SharesMathLib.VIRTUAL_SHARES
        );
        blue.withdraw(market, amountWithdrawn, 0, address(this), receiver);

        uint256 expectedSupplyShares = (amountSupplied - amountWithdrawn) * SharesMathLib.VIRTUAL_SHARES;
        assertEq(blue.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(blue.totalSupply(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(borrowableAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed - amountWithdrawn, "blue balance"
        );
    }

    function testWithdrawShares(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 sharesWithdrawn,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(blue));
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);

        uint256 expectedSupplyShares = amountSupplied * SharesMathLib.VIRTUAL_SHARES;
        uint256 availableLiquidity = amountSupplied - amountBorrowed;
        uint256 withdrawableShares = availableLiquidity.mulDivDown(
            expectedSupplyShares + SharesMathLib.VIRTUAL_SHARES, amountSupplied + SharesMathLib.VIRTUAL_ASSETS
        );

        vm.assume(withdrawableShares != 0);
        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawableShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.mulDivDown(
            amountSupplied + SharesMathLib.VIRTUAL_ASSETS, expectedSupplyShares + SharesMathLib.VIRTUAL_SHARES
        );

        borrowableAsset.setBalance(address(this), amountSupplied);
        collateralAsset.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV));
        blue.supply(market, amountSupplied, 0, address(this), hex"");

        vm.startPrank(BORROWER);
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), BORROWER, hex"");
        blue.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.Withdraw(id, address(this), address(this), receiver, expectedAmountWithdrawn, sharesWithdrawn);
        blue.withdraw(market, 0, sharesWithdrawn, address(this), receiver);

        expectedSupplyShares -= sharesWithdrawn;

        assertEq(blue.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupply(id), amountSupplied - expectedAmountWithdrawn, "total supply");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableAsset.balanceOf(receiver), expectedAmountWithdrawn, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)),
            amountSupplied - amountBorrowed - expectedAmountWithdrawn,
            "blue balance"
        );
    }

    function testWithdrawAmountOnBehalf(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountWithdrawn,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(blue));
        vm.assume(receiver != address(0) && receiver != address(blue));

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        borrowableAsset.setBalance(onBehalf, amountSupplied);
        collateralAsset.setBalance(onBehalf, amountBorrowed.wDivUp(LLTV));

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(blue), amountBorrowed.wDivUp(LLTV));
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), onBehalf, hex"");
        borrowableAsset.approve(address(blue), amountSupplied);
        blue.supply(market, amountSupplied, 0, onBehalf, hex"");
        blue.borrow(market, amountBorrowed, 0, onBehalf, onBehalf);
        blue.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 receiverBalanceBefore = borrowableAsset.balanceOf(receiver);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.Withdraw(
            id, BORROWER, onBehalf, receiver, amountWithdrawn, amountWithdrawn * SharesMathLib.VIRTUAL_SHARES
        );
        blue.withdraw(market, amountWithdrawn, 0, onBehalf, receiver);

        uint256 expectedSupplyShares = (amountSupplied - amountWithdrawn) * SharesMathLib.VIRTUAL_SHARES;

        assertEq(blue.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupply(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableAsset.balanceOf(receiver) - receiverBalanceBefore, amountWithdrawn, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed - amountWithdrawn, "blue balance"
        );
    }

    function testWithdrawShares(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 sharesWithdrawn,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(blue));
        vm.assume(receiver != address(0) && receiver != address(blue));

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);

        uint256 expectedSupplyShares = amountSupplied * SharesMathLib.VIRTUAL_SHARES;
        uint256 availableLiquidity = amountSupplied - amountBorrowed;
        uint256 withdrawableShares = availableLiquidity.mulDivDown(
            expectedSupplyShares + SharesMathLib.VIRTUAL_SHARES, amountSupplied + SharesMathLib.VIRTUAL_ASSETS
        );

        vm.assume(withdrawableShares != 0);
        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawableShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.mulDivDown(
            amountSupplied + SharesMathLib.VIRTUAL_ASSETS, expectedSupplyShares + SharesMathLib.VIRTUAL_SHARES
        );

        borrowableAsset.setBalance(onBehalf, amountSupplied);
        collateralAsset.setBalance(onBehalf, amountBorrowed.wDivUp(LLTV));

        vm.startPrank(onBehalf);
        collateralAsset.approve(address(blue), amountBorrowed.wDivUp(LLTV));
        blue.supplyCollateral(market, amountBorrowed.wDivUp(LLTV), onBehalf, hex"");
        borrowableAsset.approve(address(blue), amountSupplied);
        blue.supply(market, amountSupplied, 0, onBehalf, hex"");
        blue.borrow(market, amountBorrowed, 0, onBehalf, onBehalf);
        blue.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 receiverBalanceBefore = borrowableAsset.balanceOf(receiver);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit EventsLib.Withdraw(id, BORROWER, onBehalf, receiver, expectedAmountWithdrawn, sharesWithdrawn);
        blue.withdraw(market, 0, sharesWithdrawn, onBehalf, receiver);

        expectedSupplyShares -= sharesWithdrawn;

        assertEq(blue.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupply(id), amountSupplied - expectedAmountWithdrawn, "total supply");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(
            borrowableAsset.balanceOf(receiver) - receiverBalanceBefore, expectedAmountWithdrawn, "receiver balance"
        );
        assertEq(
            borrowableAsset.balanceOf(address(blue)),
            amountSupplied - amountBorrowed - expectedAmountWithdrawn,
            "blue balance"
        );
    }
}
