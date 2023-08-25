// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SinglePositionInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    address internal immutable USER;

    constructor() {
        USER = _addrFromHashedString("User");
    }

    function setUp() public virtual override {
        _weightSelector(this.supplyAssetsNoRevert.selector, 100);
        _weightSelector(this.supplySharesNoRevert.selector, 100);
        _weightSelector(this.withdrawAssetsNoRevert.selector, 50);
        _weightSelector(this.borrowAssetsNoRevert.selector, 15);
        _weightSelector(this.repayAssetsNoRevert.selector, 10);
        _weightSelector(this.repaySharesNoRevert.selector, 10);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralNoRevert.selector, 15);

        super.setUp();

        collateralToken.setBalance(USER, 1e30);

        vm.prank(USER);
        morpho.supplyCollateral(marketParams, 1e30, USER, hex"");

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);
    }

    function _targetSenders() internal virtual override {
        _targetSender(USER);
    }

    function supplyAssetsNoRevert(uint256 assets) public {
        assets = _boundSupplyAssets(marketParams, USER, assets);
        if (assets == 0) return;

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supply(marketParams, assets, 0, msg.sender, hex"");
    }

    function supplySharesNoRevert(uint256 shares) public {
        shares = _boundSupplyShares(marketParams, USER, shares);
        if (shares == 0) return;

        borrowableToken.setBalance(
            msg.sender, shares.toAssetsUp(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id))
        );

        vm.prank(msg.sender);
        morpho.supply(marketParams, 0, shares, msg.sender, hex"");
    }

    function withdrawAssetsNoRevert(uint256 assets, address receiver) public {
        receiver = _boundAddressNotZero(receiver);

        assets = _boundWithdrawAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, assets, 0, msg.sender, receiver);
    }

    function borrowAssetsNoRevert(uint256 assets, address receiver) public {
        receiver = _boundAddressNotZero(receiver);

        assets = _boundBorrowAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.borrow(marketParams, assets, 0, msg.sender, receiver);
    }

    function repayAssetsNoRevert(uint256 assets) public {
        assets = _boundRepayAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.repay(marketParams, assets, 0, msg.sender, hex"");
    }

    function repaySharesNoRevert(uint256 shares) public {
        shares = _boundRepayShares(marketParams, msg.sender, shares);
        if (shares == 0) return;

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);

        borrowableToken.setBalance(msg.sender, shares.toAssetsUp(totalBorrowAssets, totalBorrowShares));

        vm.prank(msg.sender);
        morpho.repay(marketParams, 0, shares, msg.sender, hex"");
    }

    function supplyCollateralNoRevert(uint256 assets) public {
        assets = _boundSupplyCollateralAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        collateralToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, assets, msg.sender, hex"");
    }

    function withdrawCollateralNoRevert(uint256 assets, address receiver) public {
        receiver = _boundAddressNotZero(receiver);

        assets = _boundWithdrawCollateralAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, assets, msg.sender, receiver);
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
