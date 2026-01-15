// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract BaseInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    address internal immutable USER;

    MarketParams[] internal allMarketParams;

    constructor() {
        USER = makeAddr("User");
    }

    function setUp() public virtual override {
        selectors.push(this.supplyAssetsOnBehalfNoRevert.selector);
        selectors.push(this.supplySharesOnBehalfNoRevert.selector);
        selectors.push(this.withdrawAssetsOnBehalfNoRevert.selector);
        selectors.push(this.borrowAssetsOnBehalfNoRevert.selector);
        selectors.push(this.repayAssetsOnBehalfNoRevert.selector);
        selectors.push(this.repaySharesOnBehalfNoRevert.selector);
        selectors.push(this.supplyCollateralOnBehalfNoRevert.selector);
        selectors.push(this.withdrawCollateralOnBehalfNoRevert.selector);

        super.setUp();

        allMarketParams.push(marketParams);

        for (uint256 i = 2; i <= 6; ++i) {
            MarketParams memory _marketParams = MarketParams({
                loanToken: address(loanToken),
                collateralToken: address(collateralToken),
                oracle: address(oracle),
                irm: address(irm),
                lltv: MAX_TEST_LLTV / i
            });

            vm.startPrank(OWNER);
            morpho.enableLltv(_marketParams.lltv);
            morpho.createMarket(_marketParams);
            vm.stopPrank();

            allMarketParams.push(_marketParams);
        }
    }

    function _targetSenders() internal virtual override {
        _targetSender(USER);
    }

    modifier authorized(address onBehalf) {
        if (onBehalf != msg.sender && !morpho.isAuthorized(onBehalf, msg.sender)) {
            vm.prank(onBehalf);
            morpho.setAuthorization(msg.sender, true);
        }

        _;

        if (morpho.isAuthorized(onBehalf, msg.sender)) {
            vm.prank(onBehalf);
            morpho.setAuthorization(msg.sender, false);
        }
    }

    function _randomMarket(uint256 marketSeed) internal view returns (MarketParams memory _marketParams) {
        return allMarketParams[marketSeed % allMarketParams.length];
    }

    function _supplyAssets(MarketParams memory _marketParams, uint256 assets, address onBehalf)
        internal
        logCall("supplyAssets")
    {
        loanToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supply(_marketParams, assets, 0, onBehalf, hex"");
    }

    function _supplyShares(MarketParams memory _marketParams, uint256 shares, address onBehalf)
        internal
        logCall("supplyShares")
    {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = morpho.expectedMarketBalances(_marketParams);

        loanToken.setBalance(msg.sender, shares.toAssetsUp(totalSupplyAssets, totalSupplyShares));

        vm.prank(msg.sender);
        morpho.supply(_marketParams, 0, shares, onBehalf, hex"");
    }

    function _withdraw(
        MarketParams memory _marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal authorized(onBehalf) logCall("withdraw") {
        vm.prank(msg.sender);
        morpho.withdraw(_marketParams, assets, shares, onBehalf, receiver);
    }

    function _borrow(
        MarketParams memory _marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal authorized(onBehalf) logCall("borrow") {
        vm.prank(msg.sender);
        morpho.borrow(_marketParams, assets, shares, onBehalf, receiver);
    }

    function _repayAssets(MarketParams memory _marketParams, uint256 assets, address onBehalf)
        internal
        logCall("repayAssets")
    {
        loanToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.repay(_marketParams, assets, 0, onBehalf, hex"");
    }

    function _repayShares(MarketParams memory _marketParams, uint256 shares, address onBehalf)
        internal
        logCall("repayShares")
    {
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(_marketParams);

        loanToken.setBalance(msg.sender, shares.toAssetsUp(totalBorrowAssets, totalBorrowShares));

        vm.prank(msg.sender);
        morpho.repay(_marketParams, 0, shares, onBehalf, hex"");
    }

    function _supplyCollateral(MarketParams memory _marketParams, uint256 assets, address onBehalf)
        internal
        logCall("supplyCollateral")
    {
        collateralToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supplyCollateral(_marketParams, assets, onBehalf, hex"");
    }

    function _withdrawCollateral(MarketParams memory _marketParams, uint256 assets, address onBehalf, address receiver)
        internal
        authorized(onBehalf)
        logCall("withdrawCollateral")
    {
        vm.prank(msg.sender);
        morpho.withdrawCollateral(_marketParams, assets, onBehalf, receiver);
    }

    function _liquidateSeizedAssets(MarketParams memory _marketParams, address borrower, uint256 seizedAssets)
        internal
        logCall("liquidateSeizedAssets")
    {
        uint256 collateralPrice = oracle.price();
        uint256 liquidationIncentiveFactor = _liquidationIncentiveFactor(_marketParams.lltv);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(_marketParams);
        uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
        uint256 repaidShares =
            seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor).toSharesUp(totalBorrowAssets, totalBorrowShares);
        uint256 repaidAssets = repaidShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        loanToken.setBalance(msg.sender, repaidAssets);

        vm.prank(msg.sender);
        morpho.liquidate(_marketParams, borrower, seizedAssets, 0, hex"");
    }

    function _liquidateRepaidShares(MarketParams memory _marketParams, address borrower, uint256 repaidShares)
        internal
        logCall("liquidateRepaidShares")
    {
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(_marketParams);

        loanToken.setBalance(msg.sender, repaidShares.toAssetsUp(totalBorrowAssets, totalBorrowShares));

        vm.prank(msg.sender);
        morpho.liquidate(_marketParams, borrower, 0, repaidShares, hex"");
    }

    /* HANDLERS */

    function setFeeNoRevert(uint256 marketSeed, uint256 newFee) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        Id _id = _marketParams.id();

        newFee = bound(newFee, 0, MAX_FEE);
        if (newFee == morpho.fee(_id)) return;

        vm.prank(OWNER);
        morpho.setFee(_marketParams, newFee);
    }

    function supplyAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomCandidate(targetSenders(), onBehalfSeed);

        assets = _boundSupplyAssets(_marketParams, USER, assets);
        if (assets == 0) return;

        _supplyAssets(_marketParams, assets, onBehalf);
    }

    function supplySharesOnBehalfNoRevert(uint256 marketSeed, uint256 shares, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomCandidate(targetSenders(), onBehalfSeed);

        shares = _boundSupplyShares(_marketParams, onBehalf, shares);
        if (shares == 0) return;

        _supplyShares(_marketParams, shares, onBehalf);
    }

    function withdrawAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed, address receiver)
        external
    {
        vm.assume(receiver != address(0));

        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomSupplier(targetSenders(), _marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawAssets(_marketParams, onBehalf, assets);
        if (assets == 0) return;

        _withdraw(_marketParams, assets, 0, onBehalf, receiver);
    }

    function borrowAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed, address receiver)
        external
    {
        vm.assume(receiver != address(0));

        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), _marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundBorrowAssets(_marketParams, onBehalf, assets);
        if (assets == 0) return;

        _borrow(_marketParams, assets, 0, onBehalf, receiver);
    }

    function repayAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomBorrower(targetSenders(), _marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundRepayAssets(_marketParams, onBehalf, assets);
        if (assets == 0) return;

        _repayAssets(_marketParams, assets, onBehalf);
    }

    function repaySharesOnBehalfNoRevert(uint256 marketSeed, uint256 shares, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomBorrower(targetSenders(), _marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        shares = _boundRepayShares(_marketParams, onBehalf, shares);
        if (shares == 0) return;

        _repayShares(_marketParams, shares, onBehalf);
    }

    function supplyCollateralOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomCandidate(targetSenders(), onBehalfSeed);

        assets = _boundSupplyCollateralAssets(_marketParams, onBehalf, assets);
        if (assets == 0) return;

        _supplyCollateral(_marketParams, assets, onBehalf);
    }

    function withdrawCollateralOnBehalfNoRevert(
        uint256 marketSeed,
        uint256 assets,
        uint256 onBehalfSeed,
        address receiver
    ) external {
        vm.assume(receiver != address(0));

        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), _marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawCollateralAssets(_marketParams, onBehalf, assets);
        if (assets == 0) return;

        _withdrawCollateral(_marketParams, assets, onBehalf, receiver);
    }

    function liquidateSeizedAssetsNoRevert(uint256 marketSeed, uint256 seizedAssets, uint256 borrowerSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address borrower = _randomUnhealthyBorrower(targetSenders(), _marketParams, borrowerSeed);
        if (borrower == address(0)) return;

        seizedAssets = _boundLiquidateSeizedAssets(_marketParams, borrower, seizedAssets);
        if (seizedAssets == 0) return;

        _liquidateSeizedAssets(_marketParams, borrower, seizedAssets);
    }

    function liquidateRepaidSharesNoRevert(uint256 marketSeed, uint256 repaidShares, uint256 borrowerSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);

        address borrower = _randomUnhealthyBorrower(targetSenders(), _marketParams, borrowerSeed);
        if (borrower == address(0)) return;

        repaidShares = _boundLiquidateRepaidShares(_marketParams, borrower, repaidShares);
        if (repaidShares == 0) return;

        _liquidateRepaidShares(_marketParams, borrower, repaidShares);
    }
}
