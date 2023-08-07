// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueInvariantBase.t.sol";

contract InvariantTest is InvariantBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());

        _weightSelector(this.supplyOnBlue.selector, 20);
        _weightSelector(this.borrowOnBlue.selector, 20);
        _weightSelector(this.repayOnBlue.selector, 20);
        _weightSelector(this.withdrawOnBlue.selector, 20);
        _weightSelector(this.supplyCollateralOnBlue.selector, 20);
        _weightSelector(this.withdrawCollateralOnBlue.selector, 20);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function _approveSendersTransfers(address[] memory senders) internal {
        for (uint256 i; i < senders.length; ++i) {
            vm.startPrank(senders[i]);
            borrowableAsset.approve(address(blue), type(uint256).max);
            collateralAsset.approve(address(blue), type(uint256).max);
            vm.stopPrank();
        }
    }

    function supplyOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.supply(market, amount, msg.sender, hex"");
    }

    function withdrawOnBlue(uint256 amount) public {
        if (blue.supplyShares(id, msg.sender) == 0) return;
        amount = bound(amount, 1, blue.supplyShares(id, msg.sender).toAssetsDown(blue.totalSupply(id),blue.totalSupplyShares(id)));
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
        if (blue.borrowShares(id, msg.sender)== 0) return;
        borrowableAsset.setBalance(msg.sender, amount);
        amount = bound(amount, 1, blue.borrowShares(id, msg.sender).toAssetsDown(blue.totalBorrow(id),blue.totalBorrowShares(id)));
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
        address[] memory senders = targetSenders();
        assertEq(sumUsersSupplyShares(senders), blue.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        address[] memory senders = targetSenders();
        assertEq(sumUsersBorrowShares(senders), blue.totalBorrowShares(id));
    }
}