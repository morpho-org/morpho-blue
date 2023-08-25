// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SinglePositionInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    uint256 internal immutable MAX_PRICE_VARIATION = 0.05e18;

    address internal immutable USER;

    constructor() {
        USER = _addrFromHashedString("User");
    }

    function setUp() public virtual override {
        _weightSelector(this.setPrice.selector, 10);
        _weightSelector(this.setFeeNoRevert.selector, 2);
        _weightSelector(this.supplyAssetsOnBehalfNoRevert.selector, 100);
        _weightSelector(this.supplySharesOnBehalfNoRevert.selector, 100);
        _weightSelector(this.withdrawAssetsOnBehalfNoRevert.selector, 50);
        _weightSelector(this.borrowAssetsOnBehalfNoRevert.selector, 75);
        _weightSelector(this.repayAssetsOnBehalfNoRevert.selector, 35);
        _weightSelector(this.repaySharesOnBehalfNoRevert.selector, 35);
        _weightSelector(this.supplyCollateralOnBehalfNoRevert.selector, 100);
        _weightSelector(this.withdrawCollateralOnBehalfNoRevert.selector, 50);
        _weightSelector(this.liquidateSeizedAssetsNoRevert.selector, 5);
        _weightSelector(this.liquidateRepaidSharesNoRevert.selector, 5);

        super.setUp();

        oracle.setPrice(ORACLE_PRICE_SCALE);
    }

    function _targetSenders() internal virtual override {
        _targetSender(USER);
    }

    modifier authorized(address onBehalf) {
        if (onBehalf != msg.sender) {
            vm.prank(onBehalf);
            morpho.setAuthorization(msg.sender, true);
        }

        _;

        vm.prank(onBehalf);
        morpho.setAuthorization(msg.sender, false);
    }

    function _borrow(
        MarketParams memory _marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal authorized(onBehalf) {
        vm.prank(msg.sender);
        morpho.borrow(_marketParams, assets, shares, onBehalf, receiver);
    }

    function _withdraw(
        MarketParams memory _marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal authorized(onBehalf) {
        vm.prank(msg.sender);
        morpho.withdraw(_marketParams, assets, shares, onBehalf, receiver);
    }

    function _withdrawCollateral(MarketParams memory _marketParams, uint256 assets, address onBehalf, address receiver)
        internal
        authorized(onBehalf)
    {
        vm.prank(msg.sender);
        morpho.withdrawCollateral(_marketParams, assets, onBehalf, receiver);
    }

    /* ACTIONS */

    function setPrice(uint256 variation) public {
        variation = bound(variation, WAD - MAX_PRICE_VARIATION, WAD + MAX_PRICE_VARIATION);

        uint256 currentPrice = IOracle(marketParams.oracle).price();

        oracle.setPrice(currentPrice.wMulDown(variation));
    }

    function setFeeNoRevert(uint256 newFee) public {
        newFee = bound(newFee, 0, MAX_FEE);
        if (newFee == morpho.fee(id)) return;

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function supplyAssetsOnBehalfNoRevert(uint256 assets, uint256 seed) public {
        address onBehalf = _randomCandidate(targetSenders(), seed);

        assets = _boundSupplyAssets(marketParams, USER, assets);
        if (assets == 0) return;

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supply(marketParams, assets, 0, onBehalf, hex"");
    }

    function supplySharesOnBehalfNoRevert(uint256 shares, uint256 seed) public {
        address onBehalf = _randomCandidate(targetSenders(), seed);

        shares = _boundSupplyShares(marketParams, onBehalf, shares);
        if (shares == 0) return;

        borrowableToken.setBalance(
            msg.sender, shares.toAssetsUp(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id))
        );

        vm.prank(msg.sender);
        morpho.supply(marketParams, 0, shares, onBehalf, hex"");
    }

    function withdrawAssetsOnBehalfNoRevert(uint256 assets, uint256 seed, address receiver) public {
        receiver = _boundAddressNotZero(receiver);

        address onBehalf = _randomSupplier(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _withdraw(marketParams, assets, 0, onBehalf, receiver);
    }

    function borrowAssetsOnBehalfNoRevert(uint256 assets, uint256 seed, address receiver) public {
        receiver = _boundAddressNotZero(receiver);

        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        assets = _boundBorrowAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _borrow(marketParams, assets, 0, onBehalf, receiver);
    }

    function repayAssetsOnBehalfNoRevert(uint256 assets, uint256 seed) public {
        address onBehalf = _randomBorrower(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        assets = _boundRepayAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.repay(marketParams, assets, 0, onBehalf, hex"");
    }

    function repaySharesOnBehalfNoRevert(uint256 shares, uint256 seed) public {
        address onBehalf = _randomBorrower(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        shares = _boundRepayShares(marketParams, onBehalf, shares);
        if (shares == 0) return;

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);

        borrowableToken.setBalance(msg.sender, shares.toAssetsUp(totalBorrowAssets, totalBorrowShares));

        vm.prank(msg.sender);
        morpho.repay(marketParams, 0, shares, onBehalf, hex"");
    }

    function supplyCollateralOnBehalfNoRevert(uint256 assets, uint256 seed) public {
        address onBehalf = _randomCandidate(targetSenders(), seed);

        assets = _boundSupplyCollateralAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        collateralToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, assets, onBehalf, hex"");
    }

    function withdrawCollateralOnBehalfNoRevert(uint256 assets, uint256 seed, address receiver) public {
        receiver = _boundAddressNotZero(receiver);

        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawCollateralAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _withdrawCollateral(marketParams, assets, onBehalf, receiver);
    }

    function liquidateSeizedAssetsNoRevert(uint256 seizedAssets, uint256 seed) public {
        address borrower = _randomUnhealthyBorrower(targetSenders(), marketParams, seed);
        if (borrower == address(0)) return;

        seizedAssets = _boundLiquidateSeizedAssets(marketParams, borrower, seizedAssets);
        if (seizedAssets == 0) return;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 repaidAssets =
            seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(_liquidationIncentive(marketParams.lltv));

        borrowableToken.setBalance(msg.sender, repaidAssets);

        vm.prank(msg.sender);
        morpho.liquidate(marketParams, borrower, seizedAssets, 0, hex"");
    }

    function liquidateRepaidSharesNoRevert(uint256 repaidShares, uint256 seed) public {
        address borrower = _randomUnhealthyBorrower(targetSenders(), marketParams, seed);
        if (borrower == address(0)) return;

        repaidShares = _boundLiquidateRepaidShares(marketParams, borrower, repaidShares);
        if (repaidShares == 0) return;

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 repaidAssets = repaidShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        borrowableToken.setBalance(msg.sender, repaidAssets);

        vm.prank(msg.sender);
        morpho.liquidate(marketParams, borrower, 0, repaidShares, hex"");
    }

    /* INVARIANTS */

    function invariantSupplyShares() public {
        assertEq(morpho.supplyShares(id, USER), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(morpho.borrowShares(id, USER), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupplyGeTotalBorrow() public {
        assertGe(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id));
    }

    function invariantMorphoBalance() public {
        assertGe(
            borrowableToken.balanceOf(address(morpho)), morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id)
        );
    }

    function invariantHealthyPosition() public {
        assertTrue(_isHealthy(marketParams, USER));
    }
}
