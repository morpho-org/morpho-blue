// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

/// @title SharesMath
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Shares management library.
/// @dev This implementation mitigates share price manipulations, using OpenZeppelin's method of virtual shares:
/// https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
library SharesMathLib {
    using FixedPointMathLib for uint256;

    uint256 internal constant VIRTUAL_SHARES = 1;

    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @dev Calculates the value of the given assets quoted in shares, rounding down.
    /// @dev Provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares.
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of the given shares quoted in assets, rounding down.
    /// @dev Provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets.
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivDown(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the value of the given assets quoted in shares, rounding up.
    /// @dev Provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares + VIRTUAL_SHARES.
    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of the given shares quoted in assets, rounding up.
    /// @dev Provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets + VIRTUAL_SHARES.
    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivUp(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }
}
