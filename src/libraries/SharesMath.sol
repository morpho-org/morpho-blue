// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {INITIAL_SHARES} from "src/libraries/Constants.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library SharesMath {
    using WadRayMath for uint256;

    /// @dev Calculates the value of the given assets quoted in shares, based on the given total assets already shared and the total number of shares held.
    /// In the edge case where no assets are currently shared (initial accounting), the value of shares is arbitrarily chosen high enough so that an inflation attack is made pointless.
    /// Note: provided that assets <= totalAssets, this function satisfies the invariant: shares <= totalShares.
    /// TODO: check maths
    function toShares(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        if (totalAssets == 0) return INITIAL_SHARES;

        return totalShares.wadMulDown(assets.wadDiv(totalAssets));
    }

    /// @dev Calculates the value of the given shares quoted in assets, based on the given total assets already shared and the total number of shares held.
    /// In the edge case where no shares are currently held (initial accounting), the value of assets is arbitrarily chosen to be 0.
    /// Note: provided that shares <= totalShares, this function satisfies the invariant: assets <= totalAssets.
    function toAssets(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        if (totalShares == 0) return 0;

        return totalAssets.wadMulDown(shares.wadDiv(totalShares));
    }
}
