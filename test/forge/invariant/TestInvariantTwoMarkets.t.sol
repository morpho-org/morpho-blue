// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueInvariantBase.t.sol";

contract TwoMarketsInvariantTest is InvariantBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;
    using MarketLib for Market;

    Irm internal irm2;
    Market public market2;
    Id public id2;

    enum ChoseMarket{
        market,
        market2
    }

    function setUp() public virtual override {
        super.setUp();
        
        irm = new Irm(blue);
        vm.label(address(irm), "IRM");

        market2 = Market(
            address(borrowableAsset),
            address(collateralAsset),
            address(borrowableOracle),
            address(collateralOracle),
            address(irm2),
            LLTV
        );
        id2 = market2.id();

        vm.startPrank(OWNER);
        blue.enableIrm(address(irm2));
        vm.stopPrank();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());

        _weightSelector(this.supplyOnBlue.selector, 20);
        _weightSelector(this.borrowOnBlue.selector, 20);
        _weightSelector(this.repayOnBlue.selector, 20);
        _weightSelector(this.withdrawOnBlue.selector, 20);
        _weightSelector(this.supplyCollateralOnBlue.selector, 20);
        _weightSelector(this.withdrawCollateralOnBlue.selector, 20);
        _weightSelector(this.newBlock.selector, 1);

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

    function supplyOnBlue(uint256 amount, ChoseMarket choseMarket) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        if (choseMarket == ChoseMarket.market){
            blue.supply(market, amount, msg.sender, hex"");
        }
        else{
            blue.supply(market2, amount, msg.sender, hex"");
        }
    }

    function withdrawOnBlue(uint256 amount, ChoseMarket choseMarket) public {
        if (blue.supplyShares(id, msg.sender) == 0) return;
        amount = bound(
            amount, 1, blue.supplyShares(id, msg.sender).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id))
        );
        vm.prank(msg.sender);
        if (choseMarket == ChoseMarket.market){
            blue.withdraw(market, amount, msg.sender, msg.sender);
        }
        else{
            blue.withdraw(market2, amount, msg.sender, msg.sender);
        }
    }

    function borrowOnBlue(uint256 amount, ChoseMarket choseMarket) public {
        if (blue.totalSupply(id) - blue.totalBorrow(id) == 0) return;
        amount = bound(amount, 1, blue.totalSupply(id) - blue.totalBorrow(id));
        vm.prank(msg.sender);
        if (choseMarket == ChoseMarket.market){
            blue.borrow(market, amount, msg.sender, msg.sender);
        }
        else{
            blue.borrow(market2, amount, msg.sender, msg.sender);
        }
    }

    function repayOnBlue(uint256 amount, ChoseMarket choseMarket) public {
        if (blue.borrowShares(id, msg.sender) == 0) return;
        borrowableAsset.setBalance(msg.sender, amount);
        amount = bound(
            amount, 1, blue.borrowShares(id, msg.sender).toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id))
        );
        vm.prank(msg.sender);
        if (choseMarket == ChoseMarket.market){
            blue.repay(market, amount, msg.sender, hex"");
        }
        else{
            blue.repay(market2, amount, msg.sender, hex"");
        }
    }

    function supplyCollateralOnBlue(uint256 amount, ChoseMarket choseMarket) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        if (choseMarket == ChoseMarket.market){
            blue.supplyCollateral(market, amount, msg.sender, hex"");
        }
        else{
            blue.supplyCollateral(market2, amount, msg.sender, hex"");
        }
    }

    function withdrawCollateralOnBlue(uint256 amount, ChoseMarket choseMarket) public {
        if (blue.collateral(id, msg.sender) == 0) return;
        amount = bound(amount, 1, blue.collateral(id, msg.sender));
        vm.prank(msg.sender);
        if (choseMarket == ChoseMarket.market){
            blue.withdrawCollateral(market, amount, msg.sender, msg.sender);
        }
        else{
            blue.withdrawCollateral(market2, amount, msg.sender, msg.sender);
        }
    }

    function invariantBlueBalance() public {
        uint256 marketAvailableAmount = blue.totalSupply(id) - blue.totalBorrow(id);
        uint256 market2AvailableAmount = blue.totalSupply(id2) - blue.totalBorrow(id2);
        assertEq(marketAvailableAmount + market2AvailableAmount, borrowableAsset.balanceOf(address(blue)));
    }
}