// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantBase.sol";

contract TwoMarketsInvariantTest is InvariantBaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;

    Irm internal irm2;
    MarketParams public marketParams2;
    Id public id2;

    function setUp() public virtual override {
        super.setUp();

        irm2 = new Irm();
        vm.label(address(irm2), "IRM2");

        marketParams2 =
            MarketParams(address(borrowableToken), address(collateralToken), address(oracle), address(irm2), LLTV + 1);
        id2 = marketParams2.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm2));
        morpho.enableLltv(LLTV + 1);
        morpho.createMarket(marketParams2);
        vm.stopPrank();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), marketParams);
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), marketParams2);

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

        blockNumber = block.number;
        timestamp = block.timestamp;

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
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

    function setMarketFee(uint256 newFee, bool changeMarket) public setCorrectBlock {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        newFee = bound(newFee, 0.1e18, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(chosenMarket, newFee);
    }

    function supplyOnMorpho(uint256 amount, bool changeMarket) public setCorrectBlock {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supply(chosenMarket, amount, 0, msg.sender, hex"");
    }

    function withdrawOnMorpho(uint256 amount, bool changeMarket) public setCorrectBlock {
        _accrueInterest(marketParams);

        (MarketParams memory chosenMarket, Id chosenId) = chooseMarket(changeMarket);

        uint256 availableLiquidity = morpho.totalSupplyAssets(chosenId) - morpho.totalBorrowAssets(chosenId);
        if (morpho.supplyShares(chosenId, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        _accrueInterest(marketParams);
        uint256 supplierBalance = morpho.supplyShares(chosenId, msg.sender).toAssetsDown(
            morpho.totalSupplyAssets(chosenId), morpho.totalSupplyShares(chosenId)
        );
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(chosenMarket, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorpho(uint256 amount, bool changeMarket) public setCorrectBlock {
        _accrueInterest(marketParams);

        (MarketParams memory chosenMarket, Id chosenId) = chooseMarket(changeMarket);

        uint256 availableLiquidity = morpho.totalSupplyAssets(chosenId) - morpho.totalBorrowAssets(chosenId);
        if (availableLiquidity == 0) return;

        _accrueInterest(marketParams);
        amount = bound(amount, 1, availableLiquidity);

        vm.prank(msg.sender);
        morpho.borrow(chosenMarket, amount, 0, msg.sender, msg.sender);
    }

    function repayOnMorpho(uint256 amount, bool changeMarket) public setCorrectBlock {
        _accrueInterest(marketParams);

        (MarketParams memory chosenMarket, Id chosenId) = chooseMarket(changeMarket);

        if (morpho.borrowShares(chosenId, msg.sender) == 0) return;

        _accrueInterest(marketParams);
        amount = bound(
            amount,
            1,
            morpho.borrowShares(chosenId, msg.sender).toAssetsDown(
                morpho.totalBorrowAssets(chosenId), morpho.totalBorrowShares(chosenId)
            )
        );

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.repay(chosenMarket, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount, bool changeMarket) public setCorrectBlock {
        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(chosenMarket, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount, bool changeMarket) public setCorrectBlock {
        _accrueInterest(marketParams);

        (MarketParams memory chosenMarket,) = chooseMarket(changeMarket);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(chosenMarket, amount, msg.sender, msg.sender);
    }

    function invariantMorphoBalance() public {
        uint256 marketAvailableAmount = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        uint256 market2AvailableAmount = morpho.totalSupplyAssets(id2) - morpho.totalBorrowAssets(id2);
        assertApproxEqAbs(marketAvailableAmount + market2AvailableAmount, borrowableToken.balanceOf(address(morpho)), 2);
    }
}
