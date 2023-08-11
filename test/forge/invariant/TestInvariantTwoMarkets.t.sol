// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueInvariantBase.t.sol";

contract TwoMarketsInvariantTest is InvariantBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using MarketLib for Market;

    Irm internal irm2;
    Market public market2;
    Id public id2;

    // enum EnumMarket{
    //     market,
    //     market2
    // }

    function setUp() public virtual override {
        super.setUp();

        irm2 = new Irm(blue);
        vm.label(address(irm2), "IRM2");

        market2 = Market(address(borrowableAsset), address(collateralAsset), address(oracle), address(irm2), LLTV + 1);
        id2 = market2.id();

        vm.startPrank(OWNER);
        blue.enableIrm(address(irm2));
        blue.enableLltv(LLTV + 1);
        blue.createMarket(market2);
        vm.stopPrank();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), market);
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), market2);

        _weightSelector(this.supplyOnBlue.selector, 20);
        _weightSelector(this.borrowOnBlue.selector, 20);
        _weightSelector(this.repayOnBlue.selector, 20);
        _weightSelector(this.withdrawOnBlue.selector, 20);
        _weightSelector(this.supplyCollateralOnBlue.selector, 20);
        _weightSelector(this.withdrawCollateralOnBlue.selector, 20);
        _weightSelector(this.newBlock.selector, 1);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function newBlock(uint8 elapsed) public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);
    }

    function supplyOnBlue(uint256 amount, bool changeMarket) public {
        Market memory chosenMarket;
        Id chosenId;
        if (!changeMarket) {
            chosenMarket = market;
            chosenId = id;
        } else {
            chosenMarket = market2;
            chosenId = id2;
        }

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.supply(chosenMarket, amount, 0, msg.sender, hex"");
    }

    function withdrawOnBlue(uint256 amount, bool changeMarket) public {
        Market memory chosenMarket;
        Id chosenId;
        if (!changeMarket) {
            chosenMarket = market;
            chosenId = id;
        } else {
            chosenMarket = market2;
            chosenId = id2;
        }

        uint256 availableLiquidity = blue.totalSupply(chosenId) - blue.totalBorrow(chosenId);
        if (blue.supplyShares(chosenId, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        _accrueInterest(chosenMarket);
        uint256 supplierBalance = blue.supplyShares(chosenId, msg.sender).toAssetsDown(
            blue.totalSupply(chosenId), blue.totalSupplyShares(chosenId)
        );
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        blue.withdraw(chosenMarket, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnBlue(uint256 amount, bool changeMarket) public {
        Market memory chosenMarket;
        Id chosenId;
        if (!changeMarket) {
            chosenMarket = market;
            chosenId = id;
        } else {
            chosenMarket = market2;
            chosenId = id2;
        }

        uint256 availableLiquidity = blue.totalSupply(chosenId) - blue.totalBorrow(chosenId);
        if (availableLiquidity == 0) return;

        _accrueInterest(chosenMarket);
        amount = bound(amount, 1, availableLiquidity);

        vm.prank(msg.sender);
        blue.borrow(chosenMarket, amount, 0, msg.sender, msg.sender);
    }

    function repayOnBlue(uint256 amount, bool changeMarket) public {
        Market memory chosenMarket;
        Id chosenId;
        if (!changeMarket) {
            chosenMarket = market;
            chosenId = id;
        } else {
            chosenMarket = market2;
            chosenId = id2;
        }
        if (blue.borrowShares(chosenId, msg.sender) == 0) return;

        _accrueInterest(chosenMarket);
        amount = bound(
            amount,
            1,
            blue.borrowShares(chosenId, msg.sender).toAssetsDown(
                blue.totalBorrow(chosenId), blue.totalBorrowShares(chosenId)
            )
        );

        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.repay(chosenMarket, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralOnBlue(uint256 amount, bool changeMarket) public {
        Market memory chosenMarket;
        Id chosenId;
        if (!changeMarket) {
            chosenMarket = market;
            chosenId = id;
        } else {
            chosenMarket = market2;
            chosenId = id2;
        }

        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralAsset.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        blue.supplyCollateral(chosenMarket, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnBlue(uint256 amount, bool changeMarket) public {
        Market memory chosenMarket;
        Id chosenId;
        if (!changeMarket) {
            chosenMarket = market;
            chosenId = id;
        } else {
            chosenMarket = market2;
            chosenId = id2;
        }

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(msg.sender);
        blue.withdrawCollateral(chosenMarket, amount, msg.sender, msg.sender);
    }

    function invariantBlueBalance() public {
        uint256 marketAvailableAmount = blue.totalSupply(id) - blue.totalBorrow(id);
        uint256 market2AvailableAmount = blue.totalSupply(id2) - blue.totalBorrow(id2);
        assertEq(marketAvailableAmount + market2AvailableAmount, borrowableAsset.balanceOf(address(blue)));
    }
}
