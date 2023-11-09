// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../BaseTest.sol";

contract MorphoLibTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;

    function _testMorphoLibCommon(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        private
    {
        // Prepare storage layout with non empty values.

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        timestamp = bound(timestamp, block.timestamp, type(uint32).max);
        fee = bound(fee, 0, MAX_FEE);

        // Set fee parameters.
        if (fee != morpho.fee(id)) {
            vm.prank(OWNER);
            morpho.setFee(marketParams, fee);
        }

        // Set timestamp.
        vm.warp(timestamp);

        loanToken.setBalance(address(this), amountSupplied);
        morpho.supply(marketParams, amountSupplied, 0, address(this), hex"");

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
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

    function testSupplyShares(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee) public {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedSupplyShares = morpho.position(id, address(this)).supplyShares;
        assertEq(morpho.supplyShares(id, address(this)), expectedSupplyShares);
    }

    function testBorrowShares(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee) public {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedBorrowShares = morpho.position(id, BORROWER).borrowShares;
        assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares);
    }

    function testCollateral(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee) public {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedCollateral = morpho.position(id, BORROWER).collateral;
        assertEq(morpho.collateral(id, BORROWER), expectedCollateral);
    }

    function testTotalSupplyAssets(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        public
    {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedTotalSupplyAssets = morpho.market(id).totalSupplyAssets;
        assertEq(morpho.totalSupplyAssets(id), expectedTotalSupplyAssets);
    }

    function testTotalSupplyShares(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        public
    {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedTotalSupplyShares = morpho.market(id).totalSupplyShares;
        assertEq(morpho.totalSupplyShares(id), expectedTotalSupplyShares);
    }

    function testTotalBorrowAssets(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        public
    {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedTotalBorrowAssets = morpho.market(id).totalBorrowAssets;
        assertEq(morpho.totalBorrowAssets(id), expectedTotalBorrowAssets);
    }

    function testTotalBorrowShares(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        public
    {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedTotalBorrowShares = morpho.market(id).totalBorrowShares;
        assertEq(morpho.totalBorrowShares(id), expectedTotalBorrowShares);
    }

    function testLastUpdate(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee) public {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedLastUpdate = morpho.market(id).lastUpdate;
        assertEq(morpho.lastUpdate(id), expectedLastUpdate);
    }

    function testFee(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee) public {
        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedFee = morpho.market(id).fee;
        assertEq(morpho.fee(id), expectedFee);
    }
}
