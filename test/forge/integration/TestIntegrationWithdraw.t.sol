// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationWithdrawTest is BaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    function testWithdrawMarketNotCreated(Market memory marketFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.withdraw(marketFuzz, 1, 0, address(this), address(this));
    }

    function testWithdrawZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.withdraw(market, 0, 0, address(this), address(this));
    }

    function testWithdrawInconsistentInput(uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.withdraw(market, amount, shares, address(this), address(this));
    }

    function testWithdrawToZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.withdraw(market, amount, 0, address(this), address(0));
    }

    function testWithdrawUnauthorized(address attacker, uint256 amount) public {
        vm.assume(attacker != address(this));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this), hex"");

        vm.prank(attacker);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        morpho.withdraw(market, amount, 0, address(this), address(this));
    }

    function testWithdrawInsufficientLiquidity(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        address supplier,
        address borrowerFuzz,
        address receiver
    ) public {
        vm.assume(supplier != address(0) && supplier != address(morpho));
        vm.assume(borrowerFuzz != address(0) && borrowerFuzz != address(morpho));
        vm.assume(receiver != address(0));

        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountSupplied = bound(amountSupplied, amountBorrowed + 1, MAX_TEST_AMOUNT + 1);

        borrowableToken.setBalance(supplier, amountSupplied);

        vm.startPrank(supplier);
        borrowableToken.approve(address(morpho), amountSupplied);
        morpho.supply(market, amountSupplied, 0, supplier, hex"");
        vm.stopPrank();

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral = amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        collateralToken.setBalance(borrowerFuzz, amountCollateral);

        vm.startPrank(borrowerFuzz);
        collateralToken.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(market, amountCollateral, borrowerFuzz, hex"");
        morpho.borrow(market, amountBorrowed, 0, borrowerFuzz, receiver);
        vm.stopPrank();

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_LIQUIDITY));
        morpho.withdraw(market, amountSupplied, 0, supplier, receiver);
    }

    function testWithdrawAssets(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountWithdrawn,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(morpho));
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral = amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        borrowableToken.setBalance(address(this), amountSupplied);
        collateralToken.setBalance(BORROWER, amountCollateral);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = amountWithdrawn.toSharesUp(amountSupplied, expectedSupplyShares);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(
            id, address(this), address(this), receiver, amountWithdrawn, expectedWithdrawnShares);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.withdraw(market, amountWithdrawn, 0, address(this), receiver);

        expectedSupplyShares -= expectedWithdrawnShares;

        assertEq(returnAssets, amountWithdrawn, "returned asset amount");
        assertEq(returnShares, expectedWithdrawnShares, "returned shares amount");
        assertEq(morpho.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(morpho.totalSupply(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(borrowableToken.balanceOf(receiver), amountWithdrawn, "receiver balance");
        assertEq(borrowableToken.balanceOf(BORROWER), amountBorrowed, "borrower balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - amountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawShares(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 sharesWithdrawn,
        address receiver
    ) public {
        vm.assume(receiver != address(0) && receiver != address(morpho));
        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral = amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 availableLiquidity = amountSupplied - amountBorrowed;
        uint256 withdrawableShares = availableLiquidity.toSharesDown(amountSupplied, expectedSupplyShares);
        vm.assume(withdrawableShares != 0);

        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawableShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.toAssetsDown(amountSupplied, expectedSupplyShares);

        borrowableToken.setBalance(address(this), amountSupplied);
        collateralToken.setBalance(BORROWER, amountCollateral);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(market, amountCollateral, BORROWER, hex"");
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, address(this), address(this), receiver, expectedAmountWithdrawn, sharesWithdrawn);
        (uint256 returnAssets, uint256 returnShares) =
            morpho.withdraw(market, 0, sharesWithdrawn, address(this), receiver);

        expectedSupplyShares -= sharesWithdrawn;

        assertEq(returnAssets, expectedAmountWithdrawn, "returned asset amount");
        assertEq(returnShares, sharesWithdrawn, "returned shares amount");
        assertEq(morpho.supplyShares(id, address(this)), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupply(id), amountSupplied - expectedAmountWithdrawn, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableToken.balanceOf(receiver), expectedAmountWithdrawn, "receiver balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - expectedAmountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawAssetsOnBehalf(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountWithdrawn,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(morpho));
        vm.assume(receiver != address(0) && receiver != address(morpho));

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);
        amountWithdrawn = bound(amountWithdrawn, 1, amountSupplied - amountBorrowed);

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral = amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        borrowableToken.setBalance(onBehalf, amountSupplied);
        collateralToken.setBalance(onBehalf, amountCollateral);

        vm.startPrank(onBehalf);
        collateralToken.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        borrowableToken.approve(address(morpho), amountSupplied);
        morpho.supply(market, amountSupplied, 0, onBehalf, hex"");
        morpho.borrow(market, amountBorrowed, 0, onBehalf, onBehalf);
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = amountWithdrawn.toSharesUp(amountSupplied, expectedSupplyShares);

        uint256 receiverBalanceBefore = borrowableToken.balanceOf(receiver);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, BORROWER, onBehalf, receiver, amountWithdrawn, expectedWithdrawnShares);
        (uint256 returnAssets, uint256 returnShares) = morpho.withdraw(market, amountWithdrawn, 0, onBehalf, receiver);

        expectedSupplyShares -= expectedWithdrawnShares;

        assertEq(returnAssets, amountWithdrawn, "returned asset amount");
        assertEq(returnShares, expectedWithdrawnShares, "returned shares amount");
        assertEq(morpho.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupply(id), amountSupplied - amountWithdrawn, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableToken.balanceOf(receiver) - receiverBalanceBefore, amountWithdrawn, "receiver balance");
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - amountWithdrawn,
            "morpho balance"
        );
    }

    function testWithdrawSharesOnBehalf(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 sharesWithdrawn,
        address onBehalf,
        address receiver
    ) public {
        vm.assume(onBehalf != address(0) && onBehalf != address(morpho));
        vm.assume(receiver != address(0) && receiver != address(morpho));

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied - 1);

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 amountCollateral = amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        uint256 expectedSupplyShares = amountSupplied.toSharesDown(0, 0);
        uint256 availableLiquidity = amountSupplied - amountBorrowed;
        uint256 withdrawableShares = availableLiquidity.toSharesDown(amountSupplied, expectedSupplyShares);
        vm.assume(withdrawableShares != 0);

        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawableShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.toAssetsDown(amountSupplied, expectedSupplyShares);

        borrowableToken.setBalance(onBehalf, amountSupplied);
        collateralToken.setBalance(onBehalf, amountCollateral);

        vm.startPrank(onBehalf);
        collateralToken.approve(address(morpho), amountCollateral);
        morpho.supplyCollateral(market, amountCollateral, onBehalf, hex"");
        borrowableToken.approve(address(morpho), amountSupplied);
        morpho.supply(market, amountSupplied, 0, onBehalf, hex"");
        morpho.borrow(market, amountBorrowed, 0, onBehalf, onBehalf);
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        uint256 receiverBalanceBefore = borrowableToken.balanceOf(receiver);

        vm.startPrank(BORROWER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Withdraw(id, BORROWER, onBehalf, receiver, expectedAmountWithdrawn, sharesWithdrawn);
        (uint256 returnAssets, uint256 returnShares) = morpho.withdraw(market, 0, sharesWithdrawn, onBehalf, receiver);

        expectedSupplyShares -= sharesWithdrawn;

        assertEq(returnAssets, expectedAmountWithdrawn, "returned asset amount");
        assertEq(returnShares, sharesWithdrawn, "returned shares amount");
        assertEq(morpho.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupply(id), amountSupplied - expectedAmountWithdrawn, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(
            borrowableToken.balanceOf(receiver) - receiverBalanceBefore, expectedAmountWithdrawn, "receiver balance"
        );
        assertEq(
            borrowableToken.balanceOf(address(morpho)),
            amountSupplied - amountBorrowed - expectedAmountWithdrawn,
            "morpho balance"
        );
    }
}
