// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../BaseTest.sol";

contract MorphoBalancesLibTest is BaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    function testVirtualAccrueInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        (
            uint256 virtualTotalSupplyAssets,
            uint256 virtualTotalSupplyShares,
            uint256 virtualTotalBorrowAssets,
            uint256 virtualTotalBorrowShares
        ) = morpho.expectedMarketBalances(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(virtualTotalSupplyAssets, morpho.totalSupplyAssets(id), "total supply assets");
        assertEq(virtualTotalBorrowAssets, morpho.totalBorrowAssets(id), "total borrow assets");
        assertEq(virtualTotalSupplyShares, morpho.totalSupplyShares(id), "total supply shares");
        assertEq(virtualTotalBorrowShares, morpho.totalBorrowShares(id), "total borrow shares");
    }

    function testExpectedTotalSupply(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalSupplyAssets = morpho.expectedTotalSupplyAssets(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(expectedTotalSupplyAssets, morpho.totalSupplyAssets(id));
    }

    function testExpectedTotalBorrow(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalBorrowAssets = morpho.expectedTotalBorrowAssets(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(expectedTotalBorrowAssets, morpho.totalBorrowAssets(id));
    }

    function testExpectedTotalSupplyShares(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalSupplyShares = morpho.expectedTotalSupplyShares(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(expectedTotalSupplyShares, morpho.totalSupplyShares(id));
    }

    function testExpectedSupplyBalance(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        internal
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedSupplyBalance = morpho.expectedSupplyAssets(marketParams, address(this));

        morpho.accrueInterest(marketParams);

        uint256 actualSupplyBalance = morpho.supplyShares(id, address(this)).toAssetsDown(
            morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id)
        );

        assertEq(expectedSupplyBalance, actualSupplyBalance);
    }

    function testExpectedBorrowBalance(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        internal
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedBorrowBalance = morpho.expectedBorrowAssets(marketParams, address(this));

        morpho.accrueInterest(marketParams);

        uint256 actualBorrowBalance = morpho.borrowShares(id, address(this)).toAssetsUp(
            morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id)
        );

        assertEq(expectedBorrowBalance, actualBorrowBalance);
    }

    function _generatePendingInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 blocks, uint256 fee)
        internal
    {
        amountSupplied = bound(amountSupplied, 0, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 0, amountSupplied);
        blocks = _boundBlocks(blocks);
        fee = bound(fee, 0, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        if (fee != morpho.fee(id)) morpho.setFee(marketParams, fee);
        vm.stopPrank();

        if (amountSupplied > 0) {
            loanToken.setBalance(address(this), amountSupplied);
            morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

            if (amountBorrowed > 0) {
                uint256 collateralPrice = oracle.price();
                collateralToken.setBalance(
                    BORROWER, amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice)
                );

                vm.startPrank(BORROWER);
                morpho.supplyCollateral(
                    marketParams,
                    amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice),
                    BORROWER,
                    hex""
                );
                morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
                vm.stopPrank();
            }
        }

        _forward(blocks);
    }
}
