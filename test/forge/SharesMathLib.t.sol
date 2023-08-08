// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {SharesMathLib} from "src/libraries/SharesMathLib.sol";

contract SharesMathLibTest is Test {
    using SharesMathLib for uint256;

    function testToSupplyShares(uint256 amount, uint256 supplyShares, uint256 totalSupply, uint256 totalSupplyShares)
        public
    {
        totalSupplyShares = bound(totalSupplyShares, SharesMathLib.VIRTUAL_SHARES, type(uint128).max);
        totalSupply = bound(totalSupply, 0, totalSupplyShares);

        supplyShares = bound(supplyShares, 0, totalSupplyShares);

        amount = bound(amount, 0, supplyShares.toAssetsDown(totalSupply, totalSupplyShares));

        assertEq(
            amount, amount.toWithdrawShares(totalSupply, totalSupplyShares).toAssetsDown(totalSupply, totalSupplyShares)
        );
    }

    function testToBorrowShares(uint256 amount, uint256 borrowShares, uint256 totalBorrow, uint256 totalBorrowShares)
        public
    {
        totalBorrowShares = bound(totalBorrowShares, SharesMathLib.VIRTUAL_SHARES, type(uint128).max);
        totalBorrow = bound(totalBorrow, 0, totalBorrowShares);

        borrowShares = bound(borrowShares, 0, totalBorrowShares);

        amount = bound(amount, 0, borrowShares.toAssetsDown(totalBorrow, totalBorrowShares));

        assertEq(
            amount, amount.toRepayShares(totalBorrow, totalBorrowShares).toAssetsUp(totalBorrow, totalBorrowShares)
        );
    }
}
