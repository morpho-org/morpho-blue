// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {UtilsLib} from "src/libraries/UtilsLib.sol";

contract UnitUtilsLibTest is Test {
    function testZeroFloorSub(uint256 x, uint256 y) public {
        assertEq(UtilsLib.zeroFloorSub(x, y), x > y ? x - y : 0);
    }

    function testExactlyOneZero(uint256 x, uint256 y) public {
        assertEq(UtilsLib.exactlyOneZero(x, y), (x != 0 && y == 0) || (x == 0 && y != 0));
    }

    function testExactlyOneZeroBothZero() public {
        assertFalse(UtilsLib.exactlyOneZero(0, 0));
    }

    function testExactlyOneZeroBothNonZero(uint256 x, uint256 y) public {
        x = bound(x, 1, type(uint256).max);
        y = bound(y, 1, type(uint256).max);
        assertFalse(UtilsLib.exactlyOneZero(x, y));
    }

    function testExactlyOneZeroFirstIsZero(uint256 y) public {
        y = bound(y, 1, type(uint256).max);
        assertTrue(UtilsLib.exactlyOneZero(0, y));
    }

    function testExactlyOneZeroSecondIsZero(uint256 x) public {
        x = bound(x, 1, type(uint256).max);
        assertTrue(UtilsLib.exactlyOneZero(x, 0));
    }
}
