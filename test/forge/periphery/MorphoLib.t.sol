// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MorphoInterestLib} from "src/libraries/periphery/MorphoInterestLib.sol";

import "../BaseTest.sol";

contract MorphoInterestLibTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;
    using MorphoInterestLib for Morpho;

    function testVirtualAccrueInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        (uint256 virtualTotalSupply, uint256 virtualTotalBorrow, uint256 virtualTotalSupplyShares) =
            morpho.expectedAccrueInterest(market);

        morpho.accrueInterest(market);

        assertEq(virtualTotalSupply, morpho.totalSupply(id), "total supply");
        assertEq(virtualTotalBorrow, morpho.totalBorrow(id), "total borrow");
        assertEq(virtualTotalSupplyShares, morpho.totalSupplyShares(id), "total supply shares");
    }

    function testExpectedTotalSupply(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalSupply = morpho.expectedTotalSupply(market);

        morpho.accrueInterest(market);

        assertEq(expectedTotalSupply, morpho.totalSupply(id));
    }

    function testExpectedTotalBorrow(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalBorrow = morpho.expectedTotalBorrow(market);

        morpho.accrueInterest(market);

        assertEq(expectedTotalBorrow, morpho.totalBorrow(id));
    }

    function testExpectedTotalSupplyShares(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalSupplyShares = morpho.expectedTotalSupplyShares(market);

        morpho.accrueInterest(market);

        assertEq(expectedTotalSupplyShares, morpho.totalSupplyShares(id));
    }

    function testExpectedSupplyBalance(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        internal
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedSupplyBalance = morpho.expectedSupplyBalance(market, address(this));

        morpho.accrueInterest(market);

        uint256 actualSupplyBalance =
            morpho.supplyShares(id, address(this)).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));

        assertEq(expectedSupplyBalance, actualSupplyBalance);
    }

    function testExpectedBorrowBalance(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        internal
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedBorrowBalance = morpho.expectedBorrowBalance(market, address(this));

        morpho.accrueInterest(market);

        uint256 actualBorrowBalance =
            morpho.borrowShares(id, address(this)).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));

        assertEq(expectedBorrowBalance, actualBorrowBalance);
    }

    function _generatePendingInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        internal
    {
        amountSupplied = bound(amountSupplied, 0, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 0, amountSupplied);
        timeElapsed = uint32(bound(timeElapsed, 0, 1e8));
        fee = bound(fee, 0, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        morpho.setFeeRecipient(OWNER);
        morpho.setFee(market, fee);
        vm.stopPrank();

        if (amountSupplied > 0) {
            borrowableToken.setBalance(address(this), amountSupplied);
            morpho.supply(market, amountSupplied, 0, address(this), hex"");

            if (amountBorrowed > 0) {
                uint256 collateralPrice = IOracle(market.oracle).price();
                collateralToken.setBalance(
                    BORROWER, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice)
                );

                vm.startPrank(BORROWER);
                morpho.supplyCollateral(
                    market, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice), BORROWER, hex""
                );
                morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
                vm.stopPrank();
            }
        }

        // New block.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + timeElapsed);
    }
}
