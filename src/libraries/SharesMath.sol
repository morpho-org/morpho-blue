// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library SharesMath {
    using FixedPointMathLib for uint256;

    /// @dev The virtual shares offset to use, as defined by OpenZeppelin in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    uint256 internal constant VIRTUAL_SHARES = 10 ** 0;

    /// @dev Calculates the value of the given assets quoted in shares, based on the given total assets already shared and the total number of shares held, rounding down.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares.
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + 1);
    }

    /// @dev Calculates the value of the given shares quoted in assets, based on the given total assets already shared and the total number of shares held, rounding down.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets.
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivDown(totalAssets + 1, totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the value of the given assets quoted in shares, based on the given total assets already shared and the total number of shares held, rounding up.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares + VIRTUAL_SHARES.
    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + VIRTUAL_SHARES, totalAssets + 1);
    }

    /// @dev Calculates the value of the given shares quoted in assets, based on the given total assets already shared and the total number of shares held, rounding up.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets + VIRTUAL_SHARES.
    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivUp(totalAssets + 1, totalShares + VIRTUAL_SHARES);
    }
}
