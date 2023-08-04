// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

/// @notice Shares management library.
/// @dev This implementation mitigates share price manipulations, using OpenZeppelin's method of virtual shares: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
library SharesMath {
    using FixedPointMathLib for uint256;

    uint256 internal constant VIRTUAL_SHARES = 1e18;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @dev Calculates the value of the given assets quoted in shares, rounding down.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares.
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of the given shares quoted in assets, rounding down.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets.
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivDown(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the value of the given assets quoted in shares, rounding up.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares + VIRTUAL_SHARES.
    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of the given shares quoted in assets, rounding up.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets + VIRTUAL_SHARES.
    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivUp(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the assets of shares corresponding to an exact assets of supply to withdraw.
    /// Note: only works as long as totalSupplyShares + VIRTUAL_SHARES >= totalSupply + VIRTUAL_ASSETS.
    function toWithdrawShares(uint256 assets, uint256 totalSupply, uint256 totalSupplyShares)
        internal
        pure
        returns (uint256)
    {
        uint256 sharesMin = toSharesDown(assets, totalSupply, totalSupplyShares);
        uint256 sharesMax = toSharesUp(assets + 1, totalSupply, totalSupplyShares);

        return (sharesMin + sharesMax) / 2;
    }

    /// @dev Calculates the assets of shares corresponding to an exact assets of debt to repay.
    /// Note: only works as long as totalBorrowShares + VIRTUAL_SHARES >= totalBorrow + VIRTUAL_ASSETS.
    function toRepayShares(uint256 assets, uint256 totalBorrow, uint256 totalBorrowShares)
        internal
        pure
        returns (uint256)
    {
        if (assets == 0) return 0;

        uint256 sharesMin = toSharesDown(assets - 1, totalBorrow, totalBorrowShares);
        uint256 sharesMax = toSharesUp(assets, totalBorrow, totalBorrowShares);

        return (sharesMin + sharesMax) / 2;
    }
}
