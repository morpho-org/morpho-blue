// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantTest.sol";

contract SingleMarketInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), marketParams);

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);

        _weightSelector(this.setMarketFee.selector, 5);
        _weightSelector(this.supplyOnMorpho.selector, 20);
        _weightSelector(this.borrowOnMorpho.selector, 15);
        _weightSelector(this.repayOnMorpho.selector, 10);
        _weightSelector(this.withdrawOnMorpho.selector, 15);
        _weightSelector(this.supplyCollateralOnMorpho.selector, 20);
        _weightSelector(this.withdrawCollateralOnMorpho.selector, 15);
        _weightSelector(this.newBlock.selector, 20);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    /* ACTIONS */

    function setMarketFee(uint256 newFee) public setCorrectBlock {
        newFee = bound(newFee, 0.1e18, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function supplyOnMorpho(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supply(marketParams, amount, 0, msg.sender, hex"");
    }

    function withdrawOnMorpho(uint256 amount) public setCorrectBlock {
        uint256 supplierBalance = morpho.expectedSupplyBalance(marketParams, msg.sender);
        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);

        amount = bound(amount, 0, min(supplierBalance, availableLiquidity));
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorpho(uint256 amount) public setCorrectBlock {
        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);

        amount = bound(amount, 0, availableLiquidity);
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.borrow(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function repayOnMorpho(uint256 amount) public setCorrectBlock {
        uint256 borrowerBalance = morpho.expectedBorrowBalance(marketParams, msg.sender);

        amount = bound(amount, 0, borrowerBalance);
        if (amount == 0) return;

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.repay(marketParams, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 0, morpho.collateral(id, msg.sender));
        if (amount == 0) return;

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
        assertEq(
            morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id), borrowableToken.balanceOf(address(morpho))
        );
    }
}
