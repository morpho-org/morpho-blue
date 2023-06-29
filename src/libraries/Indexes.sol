// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library Indexes {
    using WadRayMath for uint256;

    function toScaled(uint256 amount, uint256 index) internal pure returns (uint256) {
        return amount.wadDiv(index);
    }

    function toNormalized(uint256 amount, uint256 index) internal pure returns (uint256) {
        return amount.wadMul(index);
    }
}
