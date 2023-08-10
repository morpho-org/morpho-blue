// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueInvariantBase.t.sol";

contract SinglePositionInvariantTest is InvariantBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    address user;

    function setUp() public virtual override {
        super.setUp();

        user = _addrFromHashedString("Morpho Blue user");
        targetSender(user);

        vm.startPrank(user);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.stopPrank();

        _weightSelector(this.supplyOnBlue.selector, 20);
        _weightSelector(this.borrowOnBlue.selector, 20);
        _weightSelector(this.repayOnBlue.selector, 20);
        _weightSelector(this.withdrawOnBlue.selector, 20);
        _weightSelector(this.supplyCollateralOnBlue.selector, 20);
        _weightSelector(this.withdrawCollateralOnBlue.selector, 20);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function supplyOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.supply(market, amount, msg.sender, hex"");
    }

    function withdrawOnBlue(uint256 amount) public {
        if (blue.supplyShares(id, msg.sender) == 0) return;
        if (blue.totalSupply(id) - blue.totalBorrow(id) == 0) return;
        uint256 supplierBalance = blue.supplyShares(id, msg.sender).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));
        vm.prank(msg.sender);
        blue.withdraw(market, amount, msg.sender, msg.sender);
    }

    function borrowOnBlue(uint256 amount) public {
        if (blue.totalSupply(id) - blue.totalBorrow(id) == 0) return;
        amount = bound(amount, 1, blue.totalSupply(id) - blue.totalBorrow(id));
        vm.prank(msg.sender);
        blue.borrow(market, amount, msg.sender, msg.sender);
    }

    function repayOnBlue(uint256 amount) public {
        if (blue.borrowShares(id, msg.sender) == 0) return;
        amount = bound(
            amount, 1, blue.borrowShares(id, msg.sender).toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id))
        );
        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.repay(market, amount, msg.sender, hex"");
    }

    function supplyCollateralOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnBlue(uint256 amount) public {
        if (blue.collateral(id, msg.sender) == 0) return;
        amount = bound(amount, 1, blue.collateral(id, msg.sender));
        vm.prank(msg.sender);
        blue.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function invariantSupplyShares() public {
        assertEq(blue.supplyShares(id, user), blue.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(blue.borrowShares(id, user), blue.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        uint256 suppliedAmount = blue.supplyShares(id, user).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        assertLe(suppliedAmount, blue.totalSupply(id));
    }

    function invariantTotalBorrow() public {
        uint256 borrowedAmount = blue.borrowShares(id, user).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        assertGe(borrowedAmount, blue.totalBorrow(id));
    }

    function invariantTotalBorrowLessThanTotalSupply() public {
        assertGe(blue.totalSupply(id), blue.totalBorrow(id));
    }

    function invariantBlueBalance() public {
        assertEq(blue.totalSupply(id) - blue.totalBorrow(id), borrowableAsset.balanceOf(address(blue)));
    }

    function invariantSupplySharesRatio() public {
        if (blue.totalSupply(id) == 0) return;
        assertGe(blue.totalSupplyShares(id) / blue.totalSupply(id), SharesMath.VIRTUAL_SHARES);
    }

    function invariantBorrowSharesRatio() public {
        if (blue.totalBorrow(id) == 0) return;
        assertGe(blue.totalBorrowShares(id) / blue.totalBorrow(id), SharesMath.VIRTUAL_SHARES);
    }

    //No price changes, and no new blocks so position has to remain healthy
    function invariantHealthyPosition() public {
        assertTrue(isHealthy(market, id, user));
    }
}
