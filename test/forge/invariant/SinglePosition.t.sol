// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantTest.sol";

contract SinglePositionInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    address user;

    function setUp() public virtual override {
        super.setUp();

        user = _addrFromHashedString("User");
        targetSender(user);

        collateralToken.setBalance(user, 1e30);
        vm.startPrank(user);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams, 1e30, user, hex"");
        vm.stopPrank();

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);

        _weightSelector(this.supplyOnMorpho.selector, 20);
        _weightSelector(this.borrowOnMorpho.selector, 15);
        _weightSelector(this.repayOnMorpho.selector, 10);
        _weightSelector(this.withdrawOnMorpho.selector, 15);
        _weightSelector(this.supplyCollateralOnMorpho.selector, 20);
        _weightSelector(this.withdrawCollateralOnMorpho.selector, 15);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    /* ACTIONS */

    function supplyOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supply(marketParams, amount, 0, msg.sender, hex"");
    }

    function withdrawOnMorpho(uint256 amount) public {
        uint256 supplierBalance = morpho.expectedSupplyBalance(marketParams, msg.sender);
        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);

        amount = bound(amount, 0, min(supplierBalance, availableLiquidity));
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorpho(uint256 amount) public {
        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);

        amount = bound(amount, 0, availableLiquidity);
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.borrow(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function repayOnMorpho(uint256 amount) public {
        uint256 borrowerBalance = morpho.expectedBorrowBalance(marketParams, msg.sender);

        amount = bound(amount, 0, borrowerBalance);
        if (amount == 0) return;

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.repay(marketParams, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 0, morpho.collateral(id, msg.sender));
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, amount, msg.sender, msg.sender);
    }

    /* INVARIANTS */

    function invariantSupplyShares() public {
        assertEq(morpho.supplyShares(id, user), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(morpho.borrowShares(id, user), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        uint256 suppliedAmount = morpho.expectedSupplyBalance(marketParams, user);
        assertLe(suppliedAmount, morpho.totalSupplyAssets(id));
    }

    function invariantTotalBorrow() public {
        uint256 borrowedAmount = morpho.expectedBorrowBalance(marketParams, user);
        assertGe(borrowedAmount, morpho.totalBorrowAssets(id));
    }

    function invariantTotalSupplyGreaterThanTotalBorrow() public {
        assertGe(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id));
    }

    function invariantMorphoBalance() public {
        assertEq(
            morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id), borrowableToken.balanceOf(address(morpho))
        );
    }

    // No price changes, and no new blocks so position has to remain healthy.
    function invariantHealthyPosition() public {
        assertTrue(isHealthy(id, user));
    }
}
