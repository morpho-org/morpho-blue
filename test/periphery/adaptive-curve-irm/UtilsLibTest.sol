// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../src/periphery/adaptive-curve-irm/libraries/UtilsLib.sol";

import "../../../lib/forge-std/src/Test.sol";

contract UtilsLibTest is Test {
    using UtilsLib for int256;

    function testBoundExpected(int256 x, int256 low, int256 high) public {
        int256 expected = x <= high ? (x >= low ? x : low) : (low <= high ? high : low);
        assertEq(x.bound(low, high), expected);
    }

    function testBoundMaxMin(int256 x, int256 low, int256 high) public {
        int256 maxMin = _max(_min(x, high), low);
        assertEq(x.bound(low, high), maxMin);
    }

    function _min(int256 a, int256 b) private pure returns (int256) {
        return a > b ? b : a;
    }

    function _max(int256 a, int256 b) private pure returns (int256) {
        return a > b ? a : b;
    }
}
