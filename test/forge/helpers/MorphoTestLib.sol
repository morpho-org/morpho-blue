// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMorpho, Info} from "src/Morpho.sol";

library MorphoTestLib {
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

    function liquidate(IMorpho morpho, Info memory market, address borrower, uint256 seized, bytes memory data)
        internal
        returns (uint128 assetsRepaid, uint128 sharesRepaid)
    {
        return morpho.liquidate(market, borrower, uint128(seized), data);
    }
}
