// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract SupplyIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testSupplyMarketNotCreated(MarketParams memory marketParamsFuzz, uint256 amount) public {
        vm.assume(neq(marketParamsFuzz, marketParams));

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.supply(marketParamsFuzz, amount, 0, SUPPLIER, hex"");
    }

    function testSupplyZeroAmount() public {
        vm.assume(SUPPLIER != address(0));

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.supply(marketParams, 0, 0, SUPPLIER, hex"");
    }

    function testSupplyOnBehalfZeroAddress(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        morpho.supply(marketParams, amount, 0, address(0), hex"");
    }

    function testSupplyInconsistantInput(uint256 amount, uint256 shares) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, MAX_TEST_SHARES);

        vm.prank(SUPPLIER);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        morpho.supply(marketParams, amount, shares, address(0), hex"");
    }

    function testSupplyAssets(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(SUPPLIER, amount);

        uint256 expectedSupplyShares = amount.toSharesDown(0, 0);

        vm.prank(SUPPLIER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Supply(id, SUPPLIER, ONBEHALF, amount, expectedSupplyShares);
        (uint256 returnAssets, uint256 returnShares) = morpho.supply(marketParams, amount, 0, ONBEHALF, hex"");

        assertEq(returnAssets, amount, "returned asset amount");
        assertEq(returnShares, expectedSupplyShares, "returned shares amount");
        assertEq(morpho.supplyShares(id, ONBEHALF), expectedSupplyShares, "supply shares");
        assertEq(morpho.totalSupplyAssets(id), amount, "total supply");
        assertEq(morpho.totalSupplyShares(id), expectedSupplyShares, "total supply shares");
        assertEq(borrowableToken.balanceOf(SUPPLIER), 0, "SUPPLIER balance");
        assertEq(borrowableToken.balanceOf(address(morpho)), amount, "morpho balance");
    }

    function testSupplyShares(uint256 shares) public {
        shares = bound(shares, 1, MAX_TEST_SHARES);

        uint256 expectedSuppliedAmount = shares.toAssetsUp(0, 0);

        borrowableToken.setBalance(SUPPLIER, expectedSuppliedAmount);

        vm.prank(SUPPLIER);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.Supply(id, SUPPLIER, ONBEHALF, expectedSuppliedAmount, shares);
        (uint256 returnAssets, uint256 returnShares) = morpho.supply(marketParams, 0, shares, ONBEHALF, hex"");

        assertEq(returnAssets, expectedSuppliedAmount, "returned asset amount");
        assertEq(returnShares, shares, "returned shares amount");
        assertEq(morpho.supplyShares(id, ONBEHALF), shares, "supply shares");
        assertEq(morpho.totalSupplyAssets(id), expectedSuppliedAmount, "total supply");
        assertEq(morpho.totalSupplyShares(id), shares, "total supply shares");
        assertEq(borrowableToken.balanceOf(SUPPLIER), 0, "SUPPLIER balance");
        assertEq(borrowableToken.balanceOf(address(morpho)), expectedSuppliedAmount, "morpho balance");
    }
}
