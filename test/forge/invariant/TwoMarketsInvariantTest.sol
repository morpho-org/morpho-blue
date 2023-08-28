// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract TwoMarketsInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    IrmMock internal irm2;

    MarketParams public marketParams2;
    Id public id2;

    function setUp() public virtual override {
        _weightSelector(this.setFeeNoRevert.selector, 5);
        _weightSelector(this.supplyNoRevert.selector, 20);
        _weightSelector(this.withdrawNoRevert.selector, 15);
        _weightSelector(this.borrowNoRevert.selector, 15);
        _weightSelector(this.repayNoRevert.selector, 10);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralNoRevert.selector, 15);

        super.setUp();

        _supplyCollateralMax(targetSenders(), marketParams2);

        irm2 = new IrmMock();
        vm.label(address(irm2), "IRM2");

        marketParams2 =
            MarketParams(address(borrowableToken), address(collateralToken), address(oracle), address(irm2), LLTV + 1);
        id2 = marketParams2.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm2));
        morpho.enableLltv(LLTV + 1);
        morpho.createMarket(marketParams2);
        vm.stopPrank();

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);
    }

    function chooseMarket(bool changeMarket) internal view returns (MarketParams memory chosenMarket, Id chosenId) {
        if (!changeMarket) {
            chosenMarket = marketParams;
            chosenId = id;
        } else {
            chosenMarket = marketParams2;
            chosenId = id2;
        }
    }

    function setFeeNoRevert(uint256 newFee, bool changeMarket) public {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        newFee = bound(newFee, 0.1e18, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(chosenMarket, newFee);
    }

    function supplyNoRevert(uint256 amount, bool changeMarket) public {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supply(chosenMarket, amount, 0, msg.sender, hex"");
    }

    function withdrawNoRevert(uint256 amount, bool changeMarket) public {
        (MarketParams memory chosenMarket, Id chosenId) = chooseMarket(changeMarket);

        uint256 supplierBalance = morpho.expectedSupplyBalance(chosenMarket, msg.sender);
        uint256 availableLiquidity = morpho.totalSupplyAssets(chosenId) - morpho.totalBorrowAssets(chosenId);

        amount = bound(amount, 0, Math.min(supplierBalance, availableLiquidity));
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.withdraw(chosenMarket, amount, 0, msg.sender, msg.sender);
    }

    function borrowNoRevert(uint256 amount, bool changeMarket) public {
        (MarketParams memory chosenMarket, Id chosenId) = chooseMarket(changeMarket);

        uint256 availableLiquidity = morpho.totalSupplyAssets(chosenId) - morpho.totalBorrowAssets(chosenId);

        amount = bound(amount, 0, availableLiquidity);
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.borrow(chosenMarket, amount, 0, msg.sender, msg.sender);
    }

    function repayNoRevert(uint256 amount, bool changeMarket) public {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        amount = bound(amount, 0, morpho.expectedBorrowBalance(chosenMarket, msg.sender));
        if (amount == 0) return;

        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.repay(chosenMarket, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralNoRevert(uint256 amount, bool changeMarket) public {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(chosenMarket, amount, msg.sender, hex"");
    }

    function withdrawCollateralNoRevert(uint256 amount, bool changeMarket) public {
        (MarketParams memory chosenMarket, Id chosenId) = chooseMarket(changeMarket);

        amount = bound(amount, 0, morpho.collateral(chosenId, msg.sender));
        if (amount == 0) return;

        vm.prank(msg.sender);
        morpho.withdrawCollateral(chosenMarket, amount, msg.sender, msg.sender);
    }

    function invariantMorphoBalance() public {
        uint256 marketAvailableAmount = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        uint256 market2AvailableAmount = morpho.totalSupplyAssets(id2) - morpho.totalBorrowAssets(id2);

        assertGe(borrowableToken.balanceOf(address(morpho)), marketAvailableAmount + market2AvailableAmount);
    }
}
