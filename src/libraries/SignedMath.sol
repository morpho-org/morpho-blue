// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library SignedMath {
    using WadRayMath for uint256;

    function sadd(uint256 x, int256 y) internal pure returns (uint256) {
        return uint256(int256(x) + y);
    }

    function ssub(uint256 x, int256 y) internal pure returns (uint256) {
        return uint256(int256(x) - y);
    }

    function mulTenPowi(uint256 m, int256 e) internal pure returns (uint256) {
        if (e > 0) m *= 10 ** uint256(e);
        else if (e < 0) m /= 10 ** uint256(e);
        return m;
    }

    function wadMulDown(int256 x, uint256 y) internal pure returns (int256 z) {
        if (x >= 0) return int256(uint256(x).wadMulDown(y));
        else return -int256(uint256(-x).wadMulDown(y));
    }

    function wadDivDown(int256 x, uint256 y) internal pure returns (int256 z) {
        if (x >= 0) return int256(uint256(x).wadDivDown(y));
        else return -int256(uint256(-x).wadDivDown(y));
    }
}
