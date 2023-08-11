// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationSupplyTest is BaseTest {
    using FixedPointMathLib for uint256;

    function testSupplyMarketNotCreated(Market memory marketFuzz, address supplier, uint256 amount) public {
        vm.assume(neq(marketFuzz, market) && supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supply(marketFuzz, amount, 0, supplier, hex"");
    }

    function testSupplyZeroAmount(address supplier) public {
        vm.assume(supplier != address(0));

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.supply(market, 0, 0, supplier, hex"");
    }

    function testSupplyOnBehalfZeroAddress(address supplier, uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supply(market, amount, 0, address(0), hex"");
    }

    function testSupplyInconsistantInput(address supplier, uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        vm.prank(supplier);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.supply(market, amount, shares, address(0), hex"");
    }

    function testSupplyAmount(address supplier, address onBehalf, uint256 amount) public {
        vm.assume(supplier != address(morpho) && onBehalf != address(morpho) && onBehalf != address(0));
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(supplier, amount);

        uint256 expectedSupplyShares = amount * SharesMathLib.VIRTUAL_SHARES;

        vm.startPrank(supplier);
        borrowableAsset.approve(address(morpho), amount);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Supply(id, supplier, onBehalf, amount, expectedSupplyShares);
        morpho.supply(market, amount, 0, onBehalf, hex"");
        vm.stopPrank();

        assertEq(morpho.supplyShares(id, onBehalf), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupply(id), amount, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableAsset.balanceOf(supplier), 0, "supplier balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), amount, "morpho balance");
    }

    function testSupplyShares(address supplier, address onBehalf, uint256 shares) public {
        vm.assume(supplier != address(morpho) && onBehalf != address(morpho) && onBehalf != address(0));
        shares = bound(shares, 1, MAX_TEST_SHARES);

        uint256 expectedSuppliedAmount = shares.mulDivUp(1, SharesMathLib.VIRTUAL_SHARES);

        borrowableAsset.setBalance(supplier, expectedSuppliedAmount);

        vm.startPrank(supplier);
        borrowableAsset.approve(address(morpho), expectedSuppliedAmount);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Supply(id, supplier, onBehalf, expectedSuppliedAmount, shares);
        morpho.supply(market, 0, shares, onBehalf, hex"");
        vm.stopPrank();

        assertEq(morpho.supplyShares(id, onBehalf), shares, "supply shares");
        assertEq(morpho.totalSupply(id), expectedSuppliedAmount, "total supply");
        assertEq(morpho.totalSupplyShares(id), shares, "total supply shares");
        assertEq(borrowableAsset.balanceOf(supplier), 0, "supplier balance");
        assertEq(borrowableAsset.balanceOf(address(morpho)), expectedSuppliedAmount, "morpho balance");
    }
}
