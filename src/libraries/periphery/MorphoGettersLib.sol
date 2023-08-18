// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMorpho, Id, Info} from "src/Morpho.sol";

library MorphoLib {
    function supplyShares(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        (res,,) = morpho.user(id, user);
    }

    function borrowShares(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        (, res,) = morpho.user(id, user);
    }

    function collateral(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        (,, res) = morpho.user(id, user);
    }

    function totalSupply(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (res,,,,,) = morpho.market(id);
    }

    function totalSupplyShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (, res,,,,) = morpho.market(id);
    }

    function totalBorrow(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,, res,,,) = morpho.market(id);
    }

    function totalBorrowShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,,, res,,) = morpho.market(id);
    }

    function lastUpdate(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,,,, res,) = morpho.market(id);
    }

    function fee(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,,,,, res) = morpho.market(id);
    }

    function supply(
        IMorpho morpho,
        Info memory market,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) internal returns (uint256 assetsSupplied, uint256 sharesSupplied) {
        return morpho.supply(market, uint128(assets), uint128(shares), onBehalf, data);
    }

    function withdraw(
        IMorpho morpho,
        Info memory market,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn) {
        return morpho.withdraw(market, uint128(assets), uint128(shares), onBehalf, receiver);
    }

    function borrow(
        IMorpho morpho,
        Info memory market,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) internal returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        return morpho.borrow(market, uint128(assets), uint128(shares), onBehalf, receiver);
    }

    function repay(
        IMorpho morpho,
        Info memory market,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) internal returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        return morpho.repay(market, uint128(assets), uint128(shares), onBehalf, data);
    }

    function supplyCollateral(IMorpho morpho, Info memory market, uint256 assets, address onBehalf, bytes memory data)
        internal
    {
        morpho.supplyCollateral(market, uint128(assets), onBehalf, data);
    }

    function withdrawCollateral(IMorpho morpho, Info memory market, uint256 assets, address onBehalf, address receiver)
        internal
    {
        morpho.withdrawCollateral(market, uint128(assets), onBehalf, receiver);
    }
}
