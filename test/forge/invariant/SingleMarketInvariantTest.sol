// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SingleMarketInvariantTest is InvariantTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), marketParams);

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);

        _weightSelector(this.newBlock.selector, 20);
        _weightSelector(this.setFeeNoRevert.selector, 5);
        _weightSelector(this.supplyNoRevert.selector, 20);
        _weightSelector(this.withdrawNoRevert.selector, 15);
        _weightSelector(this.borrowNoRevert.selector, 15);
        _weightSelector(this.repayNoRevert.selector, 10);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralNoRevert.selector, 15);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function setFeeNoRevert(uint256 newFee) public setCorrectBlock {
        newFee = bound(newFee, 0.1e18, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function supplyNoRevert(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supply(marketParams, amount, 0, msg.sender, hex"");
    }

    function withdrawNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (morpho.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        uint256 supplierBalance =
            morpho.supplyShares(id, msg.sender).toAssetsDown(morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id));
        if (supplierBalance == 0) return;
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function borrowNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (availableLiquidity == 0) return;

        _accrueInterest(marketParams);
        amount = bound(amount, 1, availableLiquidity);

        vm.prank(msg.sender);
        morpho.borrow(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function repayNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        if (morpho.borrowShares(id, msg.sender) == 0) return;

        _accrueInterest(marketParams);
        uint256 borrowerBalance =
            morpho.borrowShares(id, msg.sender).toAssetsDown(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        if (borrowerBalance == 0) return;
        amount = bound(amount, 1, borrowerBalance);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.repay(marketParams, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralNoRevert(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, amount, msg.sender, hex"");
    }

    function withdrawCollateralNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, amount, msg.sender, msg.sender);
    }

    /* INVARIANTS */

    function invariantSupplyShares() public {
        assertEq(sumUsersSupplyShares(targetSenders()), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(sumUsersBorrowShares(targetSenders()), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        assertLe(sumUsersSuppliedAmounts(targetSenders()), morpho.totalSupplyAssets(id));
    }

    function invariantTotalBorrow() public {
        assertGe(sumUsersBorrowedAmounts(targetSenders()), morpho.totalBorrowAssets(id));
    }

    function invariantTotalSupplyGreaterThanTotalBorrow() public {
        assertGe(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id));
    }

    function invariantMorphoBalance() public {
        assertGe(
            borrowableToken.balanceOf(address(morpho)), morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id)
        );
    }
}
