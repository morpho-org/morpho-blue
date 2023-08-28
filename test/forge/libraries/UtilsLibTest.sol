// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/ErrorsLib.sol";
import "src/libraries/UtilsLib.sol";

contract UtilsLibTest is Test {
    using UtilsLib for uint256;

    function testExactlyOneZero(uint256 x, uint256 y) public {
        assertEq(UtilsLib.exactlyOneZero(x, y), (x > 0 && y == 0) || (x == 0 && y > 0));
    }

    function testMin(uint256 x, uint256 y) public {
        assertEq(UtilsLib.min(x, y), x < y ? x : y);
    }

    function testToUint128(uint256 x) public {
        vm.assume(x <= type(uint128).max);
        assertEq(uint256(x.toUint128()), x);
    }

    function testToUint128Revert(uint256 x) public {
        vm.assume(x > type(uint128).max);
        vm.expectRevert(bytes(ErrorsLib.MAX_UINT128_EXCEEDED));
        x.toUint128();
    }

    function testZeroFloorSub(uint256 x, uint256 y) public {
        assertEq(UtilsLib.zeroFloorSub(x, y), x < y ? 0 : x - y);
    }
}
