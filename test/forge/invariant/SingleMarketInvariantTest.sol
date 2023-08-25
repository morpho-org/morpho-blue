// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SingleMarketInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    function setUp() public virtual override {
        _weightSelector(this.setFeeNoRevert.selector, 5);
        _weightSelector(this.supplyNoRevert.selector, 20);
        _weightSelector(this.withdrawNoRevert.selector, 15);
        _weightSelector(this.borrowNoRevert.selector, 15);
        _weightSelector(this.repayNoRevert.selector, 10);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralNoRevert.selector, 15);

        super.setUp();

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);
    }

    function setFeeNoRevert(uint256 newFee) public {
        newFee = bound(newFee, 0.1e18, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function supplyNoRevert(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supply(marketParams, amount, 0, msg.sender, hex"");
    }

    function withdrawNoRevert(uint256 assets) public {
        assets = _boundWithdrawAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, assets, 0, msg.sender, msg.sender);
    }

    function borrowNoRevert(uint256 assets) public {
        assets = _boundBorrowAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.borrow(marketParams, assets, 0, msg.sender, msg.sender);
    }

    function repayNoRevert(uint256 amount) public {
        uint256 borrowerBalance = morpho.expectedBorrowBalance(marketParams, msg.sender);

        amount = bound(amount, 0, Math.min(MAX_TEST_AMOUNT, borrowerBalance));
        if (amount == 0) return;

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.repay(marketParams, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralNoRevert(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, amount, msg.sender, hex"");
    }

    function withdrawCollateralNoRevert(uint256 amount) public {
        amount = bound(amount, 0, Math.min(MAX_TEST_AMOUNT, morpho.collateral(id, msg.sender)));
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, amount, msg.sender, msg.sender);
    }

    /* INVARIANTS */

    function invariantSupplyShares() public {
        assertEq(sumSupplyShares(targetSenders()), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(sumBorrowShares(targetSenders()), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        assertLe(sumSupplyAssets(targetSenders()), morpho.totalSupplyAssets(id));
    }

    function invariantTotalBorrow() public {
        assertGe(sumBorrowAssets(targetSenders()), morpho.totalBorrowAssets(id));
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
