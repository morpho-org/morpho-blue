// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationWithdrawTest is BlueBaseTest {
    function testWithdrawUnknownMarket(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.withdraw(marketFuzz, 1, address(this), address(this));
    }

    function testWithdrawZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.withdraw(market, 0, address(this), address(this));
    }

    function testWithdrawToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdraw(market, amount, address(this), address(0));
    }

    function testWithdrawUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdraw(market, amount, address(this), address(this));
    }

    function testWithdrawInsufficientLiquidity(uint256 amountSupplied, uint256 amountBorrowed) public {
        amountSupplied = bound(amountSupplied, 1, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
        blue.withdraw(market, amountSupplied, address(this), address(this));
    }

    function testWithdraw(uint256 amountSupplied, uint256 amountBorrowed, uint256 amountWithdrawn, address receiver)
        public
    {
        vm.assume(receiver != address(0) && receiver != address(blue));

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Withdraw(
            id, address(this), address(this), receiver, amountWithdrawn, amountWithdrawn * SharesMath.VIRTUAL_SHARES
        );
        blue.withdraw(market, amountWithdrawn, address(this), receiver);

        uint256 expectedSupplyShares = (amountSupplied - amountWithdrawn) * SharesMath.VIRTUAL_SHARES;
        assertEq(blue.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(blue.totalSupply(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(borrowableAsset.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed - amountWithdrawn, "blue balance"
        );
    }

    function testWithdrawOnBehalf(
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

        vm.startPrank(onBehalf);
        borrowableAsset.approve(address(blue), amountSupplied);
        blue.supply(market, amountSupplied, onBehalf, hex"");
        blue.borrow(market, amountBorrowed, onBehalf, onBehalf);
        blue.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 receiverBalanceBefore = borrowableAsset.balanceOf(receiver);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.Withdraw(
            id, BORROWER, onBehalf, receiver, amountWithdrawn, amountWithdrawn * SharesMath.VIRTUAL_SHARES
        );
        blue.withdraw(market, amountWithdrawn, onBehalf, receiver);

        uint256 expectedSupplyShares = (amountSupplied - amountWithdrawn) * SharesMath.VIRTUAL_SHARES;

        assertEq(blue.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(blue.totalSupply(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(blue.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableAsset.balanceOf(receiver) - receiverBalanceBefore, amountWithdrawn, "receiver balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed - amountWithdrawn, "blue balance"
        );
    }
}
