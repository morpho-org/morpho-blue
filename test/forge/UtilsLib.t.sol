// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/ErrorsLib.sol";
import "src/libraries/UtilsLib.sol";

contract UtilsLibTest is Test {
    using UtilsLib for uint256;

    function testToUint128(uint256 x) public {
        vm.assume(x <= type(uint128).max);
        assertEq(uint256(x.toUint128()), x);
    }

    function testToUint128Revert(uint256 x) public {
        vm.assume(x > type(uint128).max);
        vm.expectRevert(bytes(ErrorsLib.MAX_UINT128_EXCEEDED));
        x.toUint128();
    }
}
