// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantBase.sol";

contract SinglePositionInvariantTest is InvariantBaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    address user;

    function setUp() public virtual override {
        super.setUp();

        user = _addrFromHashedString("Morpho user");
        targetSender(user);

        collateralToken.setBalance(user, 1e30);
        vm.startPrank(user);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(market, 1e30, user, hex"");
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

    function supplyOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supply(market, amount, 0, msg.sender, hex"");
    }

    function withdrawOnMorpho(uint256 amount) public {
        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (morpho.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        uint256 supplierBalance =
            morpho.supplyShares(id, msg.sender).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));
        if (supplierBalance == 0) return;
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(market, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorpho(uint256 amount) public {
        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (availableLiquidity == 0) return;

        amount = bound(amount, 1, availableLiquidity);

        vm.prank(msg.sender);
        morpho.borrow(market, amount, 0, msg.sender, msg.sender);
    }

    function repayOnMorpho(uint256 amount) public {
        if (morpho.borrowShares(id, msg.sender) == 0) return;

        uint256 borrowerBalance =
            morpho.borrowShares(id, msg.sender).toAssetsDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        if (borrowerBalance == 0) return;
        amount = bound(amount, 1, borrowerBalance);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.repay(market, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function invariantSupplyShares() public {
        assertEq(morpho.supplyShares(id, user), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(morpho.borrowShares(id, user), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        uint256 suppliedAmount =
            morpho.supplyShares(id, user).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));
        assertLe(suppliedAmount, morpho.totalSupply(id));
    }

    function invariantTotalBorrow() public {
        uint256 borrowedAmount =
            morpho.borrowShares(id, user).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        assertGe(borrowedAmount, morpho.totalBorrow(id));
    }

    function invariantTotalSupplyGreaterThanTotalBorrow() public {
        assertGe(morpho.totalSupply(id), morpho.totalBorrow(id));
    }

    function invariantMorphoBalance() public {
        assertEq(morpho.totalSupply(id) - morpho.totalBorrow(id), borrowableToken.balanceOf(address(morpho)));
    }

    // No price changes, and no new blocks so position has to remain healthy.
    function invariantHealthyPosition() public {
        assertTrue(isHealthy(market, id, user));
    }
}
