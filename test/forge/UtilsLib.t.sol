// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/UtilsLib.sol";

contract UtilsLibTest is Test {
    using UtilsLib for uint256;

    function testExactlyOneZeroTrue(uint256 x, uint256 y) public {
        vm.assume((x > 0 && y == 0) || (x == 0 && y > 0));
        assertTrue(UtilsLib.exactlyOneZero(x, y));
    }

    function testExactlyOneZeroFalse(uint256 x, uint256 y) public {
        vm.assume((x == 0 && y == 0) || (x > 0 && y > 0));
        assertFalse(UtilsLib.exactlyOneZero(x, y));
    }

    function testMin(uint256 x, uint256 y) public {
        uint256 expectedMin = x < y ? x : y;
        assertEq(UtilsLib.min(x, y), expectedMin);
    }

    function testToUint128(uint256 x) public {
        vm.assume(x <= type(uint128).max);
        assertEq(uint256(x.toUint128()), x);
    }

    function testToUint128Revert(uint256 x) public {
        vm.assume(x > type(uint128).max);
        vm.expectRevert();
        x.toUint128();
    }
}
