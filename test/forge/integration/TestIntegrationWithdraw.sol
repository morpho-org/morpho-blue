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
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_AMOUNT));
        blue.withdraw(market, 0, address(this), address(this));
    }

    function testWithdrawToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.expectRevert(bytes(Errors.ZERO_ADDRESS));
        blue.withdraw(market, amount, address(this), address(0));
    }

    function testWithdrawUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, 2 ** 64);

        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(Errors.UNAUTHORIZED));
        blue.withdraw(market, amount, address(this), address(this));
    }

    function testWithdrawUnsufficientLiquidity(uint256 amountSupplied, uint256 amountBorrowed) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        vm.expectRevert(bytes(Errors.INSUFFICIENT_LIQUIDITY));
        blue.withdraw(market, amountSupplied, address(this), address(this));
    }

    function testWithdraw(uint256 amountSupplied, uint256 amountBorrowed, uint256 amountWithdrawn) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied);
        vm.assume(amountWithdrawn <= amountSupplied - amountBorrowed);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, address(this), hex"");

        vm.prank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        blue.withdraw(market, amountWithdrawn, address(this), address(this));

        assertApproxEqAbs(
            blue.supplyShare(id, address(this)),
            (amountSupplied - amountWithdrawn) * SharesMath.VIRTUAL_SHARES,
            100,
            "supply share"
        );
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawn, "this balance");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed, "Borrower balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)), amountSupplied - amountBorrowed - amountWithdrawn, "blue balance"
        );
    }

    function testWithdrawOnBehalf(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountWithdrawn,
        uint256 amountWithdrawnToReceiver
    ) public {
        amountSupplied = bound(amountSupplied, 1, 2 ** 64);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied);
        amountWithdrawnToReceiver = bound(amountWithdrawnToReceiver, 1, amountSupplied);
        vm.assume(amountWithdrawn + amountWithdrawnToReceiver <= amountSupplied - amountBorrowed);

        borrowableAsset.setBalance(address(this), amountSupplied);
        blue.supply(market, amountSupplied, address(this), hex"");
        blue.setAuthorization(BORROWER, true);

        vm.startPrank(BORROWER);
        blue.borrow(market, amountBorrowed, BORROWER, BORROWER);

        blue.withdraw(market, amountWithdrawn, address(this), BORROWER);
        blue.withdraw(market, amountWithdrawnToReceiver, address(this), address(this));

        vm.stopPrank();

        assertEq(blue.totalSupply(id), amountSupplied - amountWithdrawn - amountWithdrawnToReceiver, "total supply");
        assertApproxEqAbs(
            blue.supplyShare(id, address(this)),
            (amountSupplied - amountWithdrawn - amountWithdrawnToReceiver) * SharesMath.VIRTUAL_SHARES,
            100,
            "supply share"
        );
        assertEq(borrowableAsset.balanceOf(address(this)), amountWithdrawnToReceiver, "this balance");
        assertEq(borrowableAsset.balanceOf(BORROWER), amountBorrowed + amountWithdrawn, "Borrower balance");
        assertEq(
            borrowableAsset.balanceOf(address(blue)),
            amountSupplied - amountBorrowed - amountWithdrawn - amountWithdrawnToReceiver,
            "blue balance"
        );
    }
}
