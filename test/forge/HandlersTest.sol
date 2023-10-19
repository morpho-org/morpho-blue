// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract HandlersTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;
    using MathLib for uint256;

    /* MODIFIERS */

    modifier logCall(string memory name) {
        console2.log(msg.sender, "->", name);

        _;
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

    /* UTILS */

    function _randomSupplier(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address)
    {
        Id _id = _marketParams.id();
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (morpho.supplyShares(_id, user) != 0) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(candidates, seed);
    }

    function _randomBorrower(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address)
    {
        Id _id = _marketParams.id();
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (morpho.borrowShares(_id, user) != 0) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(candidates, seed);
    }

    function _randomHealthyCollateralSupplier(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address)
    {
        Id _id = _marketParams.id();
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (morpho.collateral(_id, user) != 0 && _isHealthy(_marketParams, user)) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(candidates, seed);
    }

    function _randomUnhealthyBorrower(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address randomSenderToLiquidate)
    {
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (!_isHealthy(_marketParams, user)) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(candidates, seed);
    }

    /* HANDLING TOKENS */

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
        uint256 repaidAssets = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(
            _liquidationIncentiveFactor(_marketParams.lltv)
        );

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

    /* HANDLING REVERTS */

    function _setFeeNoRevert(MarketParams memory marketParams, uint256 newFee) internal {
        Id _id = marketParams.id();

        newFee = bound(newFee, 0, MAX_FEE);
        if (newFee == morpho.fee(_id)) return;

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function _supplyAssetsOnBehalfNoRevert(MarketParams memory marketParams, uint256 assets, uint256 onBehalfSeed)
        internal
    {
        address onBehalf = _randomCandidate(targetSenders(), onBehalfSeed);

        assets = _boundSupplyAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _supplyAssets(marketParams, assets, onBehalf);
    }

    function _supplySharesOnBehalfNoRevert(MarketParams memory marketParams, uint256 shares, uint256 onBehalfSeed)
        internal
    {
        address onBehalf = _randomCandidate(targetSenders(), onBehalfSeed);

        shares = _boundSupplyShares(marketParams, onBehalf, shares);
        if (shares == 0) return;

        _supplyShares(marketParams, shares, onBehalf);
    }

    function _withdrawAssetsOnBehalfNoRevert(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 onBehalfSeed,
        address receiver
    ) internal {
        receiver = _boundAddressNotZero(receiver);

        address onBehalf = _randomSupplier(targetSenders(), marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _withdraw(marketParams, assets, 0, onBehalf, receiver);
    }

    function _borrowAssetsOnBehalfNoRevert(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 onBehalfSeed,
        address receiver
    ) internal {
        receiver = _boundAddressNotZero(receiver);

        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundBorrowAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _borrow(marketParams, assets, 0, onBehalf, receiver);
    }

    function _repayAssetsOnBehalfNoRevert(MarketParams memory marketParams, uint256 assets, uint256 onBehalfSeed)
        internal
    {
        address onBehalf = _randomBorrower(targetSenders(), marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundRepayAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _repayAssets(marketParams, assets, onBehalf);
    }

    function _repaySharesOnBehalfNoRevert(MarketParams memory marketParams, uint256 shares, uint256 onBehalfSeed)
        internal
    {
        address onBehalf = _randomBorrower(targetSenders(), marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        shares = _boundRepayShares(marketParams, onBehalf, shares);
        if (shares == 0) return;

        _repayShares(marketParams, shares, onBehalf);
    }

    function _supplyCollateralOnBehalfNoRevert(MarketParams memory marketParams, uint256 assets, uint256 onBehalfSeed)
        internal
    {
        address onBehalf = _randomCandidate(targetSenders(), onBehalfSeed);

        assets = _boundSupplyCollateralAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _supplyCollateral(marketParams, assets, onBehalf);
    }

    function _withdrawCollateralOnBehalfNoRevert(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 onBehalfSeed,
        address receiver
    ) internal {
        receiver = _boundAddressNotZero(receiver);

        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), marketParams, onBehalfSeed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawCollateralAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        _withdrawCollateral(marketParams, assets, onBehalf, receiver);
    }

    function _liquidateSeizedAssetsNoRevert(
        MarketParams memory marketParams,
        uint256 seizedAssets,
        uint256 onBehalfSeed
    ) internal {
        address borrower = _randomUnhealthyBorrower(targetSenders(), marketParams, onBehalfSeed);
        if (borrower == address(0)) return;

        seizedAssets = _boundLiquidateSeizedAssets(marketParams, borrower, seizedAssets);
        if (seizedAssets == 0) return;

        _liquidateSeizedAssets(marketParams, borrower, seizedAssets);
    }

    function _liquidateRepaidSharesNoRevert(
        MarketParams memory marketParams,
        uint256 repaidShares,
        uint256 onBehalfSeed
    ) internal {
        address borrower = _randomUnhealthyBorrower(targetSenders(), marketParams, onBehalfSeed);
        if (borrower == address(0)) return;

        repaidShares = _boundLiquidateRepaidShares(marketParams, borrower, repaidShares);
        if (repaidShares == 0) return;

        _liquidateRepaidShares(marketParams, borrower, repaidShares);
    }
}
