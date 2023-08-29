// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract WithdrawIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testWithdrawMarketNotCreated(MarketParams memory marketParamsParamsFuzz) public {
        vm.assume(neq(marketParamsParamsFuzz, marketParams));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdraw(marketParamsParamsFuzz, 1, 0, address(this), address(this));
    }

    function testWithdrawZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.withdraw(marketParams, 0, 0, address(this), address(this));
    }

    function testWithdrawInconsistentInput(uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.withdraw(marketParams, amount, shares, address(this), address(this));
    }

    function testWithdrawToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdraw(marketParams, amount, 0, address(this), address(0));
    }

    function testWithdrawUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdraw(marketParams, amount, 0, address(this), address(this));
    }

    function testWithdrawInsufficientLiquidity(uint256 amountSupplied, uint256 amountBorrowed) public {
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) =
            _boundHealthyPosition(0, amountBorrowed, IOracle(marketParams.oracle).price());
        amountSupplied = bound(amountSupplied, amountBorrowed + 1, MAX_TEST_AMOUNT + 1);

        borrowableToken.setBalance(SUPPLIER, amountSupplied);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, RECEIVER);
        vm.stopPrank();

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
        morpho.withdraw(marketParams, amountSupplied, 0, SUPPLIER, RECEIVER);
    }

    function testWithdrawAssets(uint256 amountSupplied, uint256 amountBorrowed, uint256 amountWithdrawn) public {
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) =
            _boundHealthyPosition(0, amountBorrowed, IOracle(marketParams.oracle).price());
        vm.assume(amountBorrowed < MAX_TEST_AMOUNT);
        amountSupplied = bound(amountSupplied, amountBorrowed + 1, MAX_TEST_AMOUNT);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        borrowableToken.setBalance(address(this), amountSupplied);
        collateralToken.setBalance(BORROWER, amountCollateral);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = amountWithdrawn.toSharesUp(amountSupplied, expectedSupplyShares);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, address(this), address(this), RECEIVER, amountWithdrawn, expectedWithdrawnShares);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.withdraw(marketParams, amountWithdrawn, 0, address(this), RECEIVER);

        expectedSupplyShares -= expectedWithdrawnShares;

        assertEq(returnAssets, amountWithdrawn, "returned asset amount");
        assertEq(returnShares, expectedWithdrawnShares, "returned shares amount");
        assertEq(morpho.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(morpho.totalSupplyAssets(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(borrowableToken.balanceOf(RECEIVER), amountWithdrawn, "RECEIVER balance");
        assertEq(borrowableToken.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - amountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawShares(uint256 amountSupplied, uint256 amountBorrowed, uint256 sharesWithdrawn) public {
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) =
            _boundHealthyPosition(0, amountBorrowed, IOracle(marketParams.oracle).price());
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 availableLiquidity = amountSupplied - amountBorrowed;
        uint256 withdrawableShares = availableLiquidity.toSharesDown(amountSupplied, expectedSupplyShares);
        vm.assume(withdrawableShares != 0);

        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawableShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.toAssetsDown(amountSupplied, expectedSupplyShares);

        borrowableToken.setBalance(address(this), amountSupplied);
        collateralToken.setBalance(BORROWER, amountCollateral);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, address(this), address(this), RECEIVER, expectedAmountWithdrawn, sharesWithdrawn);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.withdraw(marketParams, 0, sharesWithdrawn, address(this), RECEIVER);

        expectedSupplyShares -= sharesWithdrawn;

        assertEq(returnAssets, expectedAmountWithdrawn, "returned asset amount");
        assertEq(returnShares, sharesWithdrawn, "returned shares amount");
        assertEq(morpho.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupplyAssets(id), amountSupplied - expectedAmountWithdrawn, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableToken.balanceOf(RECEIVER), expectedAmountWithdrawn, "RECEIVER balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - expectedAmountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawAssetsOnBehalf(uint256 amountSupplied, uint256 amountBorrowed, uint256 amountWithdrawn)
        public
    {
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) =
            _boundHealthyPosition(0, amountBorrowed, IOracle(marketParams.oracle).price());
        vm.assume(amountBorrowed < MAX_TEST_AMOUNT);
        amountSupplied = bound(amountSupplied, amountBorrowed + 1, MAX_TEST_AMOUNT);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        borrowableToken.setBalance(ONBEHALF, amountSupplied);
        collateralToken.setBalance(ONBEHALF, amountCollateral);

        vm.startPrank(ONBEHALF);
        morpho.supplyCollateral(marketParams, amountCollateral, ONBEHALF, hex"");
        morpho.supply(marketParams, amountSupplied, 0, ONBEHALF, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, ONBEHALF, ONBEHALF);
        vm.stopPrank();

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = amountWithdrawn.toSharesUp(amountSupplied, expectedSupplyShares);

        uint256 receiverBalanceBefore = borrowableToken.balanceOf(RECEIVER);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, BORROWER, ONBEHALF, RECEIVER, amountWithdrawn, expectedWithdrawnShares);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.withdraw(marketParams, amountWithdrawn, 0, ONBEHALF, RECEIVER);

        expectedSupplyShares -= expectedWithdrawnShares;

        assertEq(returnAssets, amountWithdrawn, "returned asset amount");
        assertEq(returnShares, expectedWithdrawnShares, "returned shares amount");
        assertEq(morpho.supplyShares(id, ONBEHALF), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupplyAssets(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableToken.balanceOf(RECEIVER) - receiverBalanceBefore, amountWithdrawn, "RECEIVER balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - amountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawSharesOnBehalf(uint256 amountSupplied, uint256 amountBorrowed, uint256 sharesWithdrawn)
        public
    {
        uint256 amountCollateral;
        (amountCollateral, amountBorrowed,) =
            _boundHealthyPosition(0, amountBorrowed, IOracle(marketParams.oracle).price());
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 availableLiquidity = amountSupplied - amountBorrowed;
        uint256 withdrawableShares = availableLiquidity.toSharesDown(amountSupplied, expectedSupplyShares);
        vm.assume(withdrawableShares != 0);

        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawableShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.toAssetsDown(amountSupplied, expectedSupplyShares);

        borrowableToken.setBalance(ONBEHALF, amountSupplied);
        collateralToken.setBalance(ONBEHALF, amountCollateral);

        vm.startPrank(ONBEHALF);
        morpho.supplyCollateral(marketParams, amountCollateral, ONBEHALF, hex"");
        morpho.supply(marketParams, amountSupplied, 0, ONBEHALF, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, ONBEHALF, ONBEHALF);
        vm.stopPrank();

        uint256 receiverBalanceBefore = borrowableToken.balanceOf(RECEIVER);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, BORROWER, ONBEHALF, RECEIVER, expectedAmountWithdrawn, sharesWithdrawn);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.withdraw(marketParams, 0, sharesWithdrawn, ONBEHALF, RECEIVER);

        expectedSupplyShares -= sharesWithdrawn;

        assertEq(returnAssets, expectedAmountWithdrawn, "returned asset amount");
        assertEq(returnShares, sharesWithdrawn, "returned shares amount");
        assertEq(morpho.supplyShares(id, ONBEHALF), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupplyAssets(id), amountSupplied - expectedAmountWithdrawn, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(
            borrowableToken.balanceOf(RECEIVER) - receiverBalanceBefore, expectedAmountWithdrawn, "RECEIVER balance"
        );
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - expectedAmountWithdrawn,
            "morpho balance"
        );
    }
}
