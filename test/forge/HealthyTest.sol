// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/console2.sol";

import "src/mocks/IrmArbitraryMock.sol";
import "./HandlersTest.sol";

contract HealthyTest is HandlersTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    address sender;

    function setUp() public override {
        super.setUp();
        IrmArbitraryMock arbitraryIrm = new IrmArbitraryMock();
        arbitraryIrm.setRate(uint256(5e16) / 365 days); // 5% APR // TODO: test with random rate
        irm = arbitraryIrm;
        vm.prank(OWNER);
        morpho.enableIrm(address(irm));
        _setLltv(marketParams.lltv);
    }

    uint256 internal constant N = 4; // TODO: test with a larger N

    uint256 internal constant MIN_VALUE = 1e7;

    struct Init {
        address[N] user;
        uint256[N] collateral;
        uint256[N] supply;
        uint256[N] borrow;
        uint256 roll;
        uint256 warp;
    }

    function _setUpMarket(Init memory init) public {
        uint256 maxElapsed = 14 days; // TODO: test with random values
        uint256 maxBorrowMargin = 0.00191e18; // TODO: can be advantageously transformed into a precomputed formula

        sender = userOf(init, 0);
        _targetSender(sender);

        for (uint256 i = 0; i < N; i++) {
            address user = userOf(init, i);
            uint256 collateral = init.collateral[i];
            uint256 supply = init.supply[i];
            uint256 borrow = init.borrow[i];

            // supply

            collateral = bound(collateral, MIN_VALUE, type(uint128).max);
            supply = bound(supply, MIN_VALUE, type(uint128).max / 1e6);

            collateralToken.setBalance(user, type(uint128).max);
            loanToken.setBalance(user, type(uint128).max);

            vm.startPrank(user);
            collateralToken.approve(address(morpho), type(uint256).max);
            loanToken.approve(address(morpho), type(uint256).max);
            if (collateral > 0) morpho.supplyCollateral(marketParams, collateral, user, "");
            if (supply > 0) morpho.supply(marketParams, supply, 0, user, "");
            vm.stopPrank();

            // borrow

            uint256 maxBorrow = _maxBorrow(marketParams, user) * (1e18 - maxBorrowMargin) / 1e18;
            uint256 liquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
            borrow = bound(borrow, 1, UtilsLib.min(maxBorrow, liquidity));

            vm.startPrank(user);
            if (borrow > 0) morpho.borrow(marketParams, borrow, 0, user, user);
            vm.stopPrank();
        }

        vm.roll(block.number + bound(init.roll, 0, 2 ** 64));
        vm.warp(block.timestamp + bound(init.warp, 0, maxElapsed));
    }

    function setUpMarket(Init memory init) public {
        (bool success,) = address(this).call(abi.encodeWithSelector(this._setUpMarket.selector, init));
        vm.assume(success);
    }

    function _targetSender(address _sender) internal {
        targetSender(_sender);

        vm.startPrank(_sender);
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    function testHealthinessPreservation(Init memory init, uint256 assets, uint256 seed) public {
        setUpMarket(init);

        assets = bound(assets, 1, 1e33); // round-up(2^128 / 10^6)

        vm.assume(morphoIsHealthy(marketParams, sender));

        loanToken.setBalance(sender, type(uint128).max);
        _supplyAssetsOnBehalfNoRevert(marketParams, assets, seed);

        assert(morphoIsHealthy(marketParams, sender));
    }

    function userOf(Init memory init, uint256 i) internal pure returns (address user) {
        user = init.user[i];
        // to avoid too many zero address failures
        // TODO: test zero address cases separately
        if (user == address(0)) user = address(1);
    }

    function morphoIsHealthy(MarketParams memory _marketParams, address borrower) public view returns (bool) {
        Id _id = marketParams.id();
        uint256 maxBorrow = _maxBorrow(_marketParams, borrower);
        uint256 borrowed =
            morpho.borrowShares(_id, borrower).toAssetsUp(morpho.totalBorrowAssets(_id), morpho.totalBorrowShares(_id));

        return maxBorrow >= borrowed;
    }
}
