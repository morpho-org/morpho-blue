// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueInvariantBase.t.sol";

contract SingleMarketInvariantTest is InvariantBaseTest {
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
        _weightSelector(this.newBlock.selector, 5);
        _weightSelector(this.setMarketFee.selector, 2);

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

    function newBlock(uint8 elapsed) public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);
    }

    function setMarketFee(uint256 newFee) public {
        newFee = bound(newFee, 0, MAX_FEE);

        vm.prank(OWNER);
        blue.setFee(market, newFee);
    }

    function supplyOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.supply(market, amount, msg.sender, hex"");
    }

    function withdrawOnBlue(uint256 amount) public {
        if (blue.supplyShares(id, msg.sender) == 0) return;
        amount = bound(
            amount, 1, blue.supplyShares(id, msg.sender).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id))
        );
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
        borrowableAsset.setBalance(msg.sender, amount);
        amount = bound(
            amount, 1, blue.borrowShares(id, msg.sender).toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id))
        );
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

    function invariantTotalSupply() public {
        address[] memory senders = targetSenders();
        assertLe(sumUsersSuppliedAmounts(senders), blue.totalSupply(id));
    }

    function invariantTotalBorrow() public {
        address[] memory senders = targetSenders();
        assertGe(sumUsersBorrowedAmounts(senders), blue.totalBorrow(id));
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
}
