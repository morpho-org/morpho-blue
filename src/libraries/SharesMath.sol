// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VIRTUAL_SHARES} from "./Constants.sol";

import {WadRayMath} from "morpho-utils/math/WadRayMath.sol";

library SharesMath {
    using WadRayMath for uint;

    /// @dev Calculates the value of the given assets quoted in shares, based on the given total assets already shared and the total number of shares held, rounding down.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares.
    function toSharesDown(uint assets, uint totalAssets, uint totalShares) internal pure returns (uint) {
        return assets.wadDivDown(totalAssets + 1).wadMulDown(totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the value of the given shares quoted in assets, based on the given total assets already shared and the total number of shares held, rounding down.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets.
    function toAssetsDown(uint shares, uint totalAssets, uint totalShares) internal pure returns (uint) {
        return shares.wadDivDown(totalShares + VIRTUAL_SHARES).wadMulDown(totalAssets + 1);
    }

    /// @dev Calculates the value of the given assets quoted in shares, based on the given total assets already shared and the total number of shares held, rounding up.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares.
    function toSharesUp(uint assets, uint totalAssets, uint totalShares) internal pure returns (uint) {
        return assets.wadDivUp(totalAssets + 1).wadMulUp(totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the value of the given shares quoted in assets, based on the given total assets already shared and the total number of shares held, rounding up.
    /// This implementation relies on OpenZeppelin's virtual shares calculation to mitigate share price manipulations, as defined in: https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets.
    function toAssetsUp(uint shares, uint totalAssets, uint totalShares) internal pure returns (uint) {
        return shares.wadDivUp(totalShares + VIRTUAL_SHARES).wadMulUp(totalAssets + 1);
    }
}
