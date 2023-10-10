// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/console2.sol";

import "src/mocks/IrmArbitraryMock.sol";
import "../BaseTest.sol";

contract HealthyTest is BaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

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

    uint256 internal constant MIN_VALUE = 1e7; // 0.1 WBTC

    struct Init {
        address[N] user;
        uint256[N] collateral;
        uint256[N] supply;
        uint256[N] borrow;
        uint256 roll;
        uint256 warp;
    }

    function userOf(Init memory init, uint256 i) internal pure returns (address user) {
        user = init.user[i];
        // to avoid too many zero address failures
        // TODO: test zero address cases separately
        if (user == address(0)) user = address(1);
    }

    function _setUpMarket(Init memory init) public {
        uint256 maxElapsed = 14 days; // TODO: test with random values
        uint256 maxBorrowMargin = 0.00191e18; // TODO: can be advantageously transformed into a precomputed formula

        for (uint256 i = 0; i < N; i++) {
            address user = userOf(init, i);
            uint256 collateral = init.collateral[i];
            uint256 supply = init.supply[i];
            uint256 borrow = init.borrow[i];

            // supply

            collateral = bound(collateral, MIN_VALUE, type(uint128).max);
            supply = bound(supply, MIN_VALUE, type(uint128).max / 1e6);

            //collateral = bound(collateral, 0, type(uint128).max - morpho.collateral(id, user)); // bounded to keep the
            // resulting user's collateral < 2**128
            //supply     = bound(supply,     0, (type(uint128).max - morpho.totalSupplyShares(id)) / VIRTUAL_SHARES); //
            // bounded to keep the resulting total supply shares < 2**128

            collateralToken.setBalance(user, type(uint128).max);
            loanToken.setBalance(user, type(uint128).max);

            //collateralToken.setBalance(user, collateral);
            //loanToken.setBalance(user, supply);

            vm.startPrank(user);

            collateralToken.approve(address(morpho), type(uint256).max);
            loanToken.approve(address(morpho), type(uint256).max);

            if (collateral > 0) morpho.supplyCollateral(marketParams, collateral, user, "");
            if (supply > 0) morpho.supply(marketParams, supply, 0, user, "");

            vm.stopPrank();

            // borrow

            uint256 maxBorrow = min(
                morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id), // remaining supply
                collateral.mulDivDown(IOracle(marketParams.oracle).price(), ORACLE_PRICE_SCALE).wMulDown(
                    marketParams.lltv
                ) // remaining collateral
            );
            borrow = bound(borrow, 1, maxBorrow * (1e18 - maxBorrowMargin) / 1e18);

            vm.startPrank(user);
            if (borrow > 0) morpho.borrow(marketParams, borrow, 0, user, user);
            vm.stopPrank();
        }

        vm.roll(block.number + bound(init.roll, 0, 2 ** 64));
        vm.warp(block.timestamp + bound(init.warp, 0, maxElapsed));
    }

    function setUpMarket(Init memory init) public {
        //_setUpMarket(init);
        (bool success,) = address(this).call(abi.encodeWithSelector(this._setUpMarket.selector, init));
        vm.assume(success);

        logMarket(init);
    }

    function logMarket(Init memory init) internal view {
        uint256 totalSupplyAssets = morpho.totalSupplyAssets(id);
        uint256 totalSupplyShares = morpho.totalSupplyShares(id);
        uint256 totalBorrowAssets = morpho.totalBorrowAssets(id);
        uint256 totalBorrowShares = morpho.totalBorrowShares(id);

        console2.log("totalSupplyAssets", totalSupplyAssets);
        console2.log("totalSupplyShares", totalSupplyShares);
        console2.log("totalBorrowAssets", totalBorrowAssets);
        console2.log("totalBorrowShares", totalBorrowShares);

        uint256 price = IOracle(marketParams.oracle).price();

        for (uint256 i = 0; i < N; i++) {
            address user = userOf(init, i);

            uint256 supplyShares = morpho.supplyShares(id, user);
            uint256 borrowShares = morpho.borrowShares(id, user);

            console2.log("supplyAssets", user, supplyShares.toAssetsUp(totalSupplyAssets, totalSupplyShares));
            console2.log("supplyShares", user, supplyShares);
            console2.log("borrowAssets", user, borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares));
            console2.log("borrowShares", user, borrowShares);

            uint256 collateral = morpho.collateral(id, user);
            console2.log(
                "collateral  ",
                user,
                collateral.mulDivDown(price, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv),
                collateral
            );

            console2.log("value       ", user, value(user));
        }
    }

    function value(address user) internal view returns (uint256) {
        uint256 totalBorrowAssets = morpho.totalBorrowAssets(id);
        uint256 totalBorrowShares = morpho.totalBorrowShares(id);

        uint256 borrowShares = morpho.borrowShares(id, user);
        uint256 borrowAssets = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        uint256 price = IOracle(marketParams.oracle).price();
        uint256 collateral = morpho.collateral(id, user).mulDivDown(price, ORACLE_PRICE_SCALE);

        return collateral - borrowAssets;
    }

    /*
    function test_setup(Init memory init) public {
        setUpMarket(init);
    }
    */

    // Property A.1 in https://github.com/morpho-labs/morpho-blue/issues/256
    function testHealthinessPreservation(Init memory init, bool assets_or_shares, uint256 amount, uint256 selector)
        public
    {
        setUpMarket(init);

        address sender = userOf(init, 0);

        address onBehalf = sender;
        address receiver = sender; // TODO: test with other receivers

        bytes memory data = ""; // TODO: test with callbacks

        uint256 assets = 0;
        uint256 shares = 0;
        if (assets_or_shares) {
            assets = bound(amount, 1, 1e33); // round-up(2^128 / 10^6)
        } else {
            shares = bound(amount, 1, 1e39); // round-up(2^128)
        }

        vm.assume(morphoIsHealthy(marketParams, sender));

        // TODO: can probably be advantageously transformed into an forge invariant
        selector = selector % 7;
        if (selector == 0) {
            loanToken.setBalance(sender, type(uint128).max);
            vm.prank(sender);
            morphoSupply(marketParams, assets, shares, onBehalf, data);
            console2.log("supply", assets, shares);
        } else if (selector == 1) {
            vm.prank(sender);
            morphoWithdraw(marketParams, assets, shares, onBehalf, receiver);
            console2.log("withdraw", assets, shares);
        } else if (selector == 2) {
            vm.prank(sender);
            morphoBorrow(marketParams, assets, shares, onBehalf, receiver);
            console2.log("borrow", assets, shares);
        } else if (selector == 3) {
            loanToken.setBalance(sender, type(uint128).max);
            vm.prank(sender);
            morphoRepay(marketParams, assets, shares, onBehalf, data);
            console2.log("repay", assets, shares);
        } else if (selector == 4) {
            collateralToken.setBalance(sender, type(uint128).max);
            assets = bound(amount, 1, 1e39); // round-up(2^128)
            vm.prank(sender);
            morphoSupplyCollateral(marketParams, assets, onBehalf, data);
            console2.log("supplyCollateral", assets);
        } else if (selector == 5) {
            assets = bound(amount, 1, 1e39); // round-up(2^128)
            vm.prank(sender);
            morphoWithdrawCollateral(marketParams, assets, onBehalf, receiver);
            console2.log("withdrawCollateral", assets);
        } else {
            loanToken.setBalance(sender, type(uint128).max);
            address borrower = userOf(init, 1);
            vm.prank(sender);
            morphoLiquidate(marketParams, borrower, assets, shares, data);
            console2.log("liquidate", assets, shares);
        }

        logMarket(init);

        assert(morphoIsHealthy(marketParams, sender));
    }

    function morphoIsHealthy(MarketParams memory _marketParams, address borrower) public view returns (bool) {
        Id _id = marketParams.id();
        uint256 maxBorrow = _maxBorrow(_marketParams, borrower);
        uint256 borrowed =
            morpho.borrowShares(_id, borrower).toAssetsUp(morpho.totalBorrowAssets(_id), morpho.totalBorrowShares(_id));

        return maxBorrow >= borrowed;
    }

    function morphoSupply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) internal returns (uint256, uint256) {
        bytes memory retdata =
            _callMorpho(abi.encodeWithSelector(Morpho.supply.selector, marketParams, assets, shares, onBehalf, data));
        return abi.decode(retdata, (uint256, uint256));
    }

    function morphoWithdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal returns (uint256, uint256) {
        bytes memory retdata = _callMorpho(
            abi.encodeWithSelector(Morpho.withdraw.selector, marketParams, assets, shares, onBehalf, receiver)
        );
        return abi.decode(retdata, (uint256, uint256));
    }

    function morphoBorrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal returns (uint256, uint256) {
        bytes memory retdata = _callMorpho(
            abi.encodeWithSelector(Morpho.borrow.selector, marketParams, assets, shares, onBehalf, receiver)
        );
        return abi.decode(retdata, (uint256, uint256));
    }

    function morphoRepay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) internal returns (uint256, uint256) {
        bytes memory retdata =
            _callMorpho(abi.encodeWithSelector(Morpho.repay.selector, marketParams, assets, shares, onBehalf, data));
        return abi.decode(retdata, (uint256, uint256));
    }

    function morphoSupplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) internal {
        _callMorpho(abi.encodeWithSelector(Morpho.supplyCollateral.selector, marketParams, assets, onBehalf, data));
    }

    function morphoWithdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) internal {
        _callMorpho(
            abi.encodeWithSelector(Morpho.withdrawCollateral.selector, marketParams, assets, onBehalf, receiver)
        );
    }

    function morphoLiquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 assets,
        uint256 shares,
        bytes memory data
    ) internal returns (uint256, uint256) {
        bytes memory retdata =
            _callMorpho(abi.encodeWithSelector(Morpho.liquidate.selector, marketParams, borrower, assets, shares, data));
        return abi.decode(retdata, (uint256, uint256));
    }

    function _callMorpho(bytes memory data) internal returns (bytes memory retdata) {
        bool success;
        (success, retdata) = address(morpho).call(data);
        vm.assume(success); // if reverted, discard the current fuzz inputs, and let the fuzzer to start a new fuzz run
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
