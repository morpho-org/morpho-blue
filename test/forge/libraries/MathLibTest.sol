// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/MathLib.sol";
import "test/forge/helpers/WadMath.sol";

contract MathLibTest is Test {
    using MathLib for uint256;

    function testWTaylorCompounded(uint256 rate, uint256 timeElapsed) public {
        // Assume rate is less than a ~500% APY. (~180% APR)
        rate = bound(rate, 0, WAD / 20_000_000);
        timeElapsed = bound(timeElapsed, 0, 365 days);
        uint256 result = rate.wTaylorCompounded(timeElapsed) + WAD;
        uint256 toCompare = WadMath.wadExpUp(rate * timeElapsed);
        assertLe(result, toCompare, "rate should be less than the compounded rate");
        assertGe(result, WAD + timeElapsed * rate, "rate should be greater than the simple interest rate");
        assertLe((toCompare - result) * 100_00 / toCompare, 8_00, "The error should be less than or equal to 8%");
    }

    function testMulDivDown(uint256 x, uint256 y, uint256 denominator) public {
        // Ignore cases where x * y overflows or denominator is 0.
        unchecked {
            if (denominator == 0 || (x != 0 && (x * y) / x != y)) return;
        }

        assertEq(MathLib.mulDivDown(x, y, denominator), (x * y) / denominator);
    }

    function testMulDivDownOverflow(uint256 x, uint256 y, uint256 denominator) public {
        denominator = bound(denominator, 1, type(uint256).max);
        // Overflow if
        //     x * y > type(uint256).max
        // <=> y > 0 and x > type(uint256).max / y
        // With
        //     type(uint256).max / y < type(uint256).max
        // <=> y > 1
        y = bound(y, 2, type(uint256).max);
        x = bound(x, type(uint256).max / y + 1, type(uint256).max);

        vm.expectRevert();
        MathLib.mulDivDown(x, y, denominator);
    }

    function testMulDivDownZeroDenominator(uint256 x, uint256 y) public {
        vm.expectRevert();
        MathLib.mulDivDown(x, y, 0);
    }

    function testMulDivUp(uint256 x, uint256 y, uint256 denominator) public {
        denominator = bound(denominator, 1, type(uint256).max - 1);
        y = bound(y, 1, type(uint256).max);
        x = bound(x, 0, (type(uint256).max - denominator - 1) / y);

        assertEq(MathLib.mulDivUp(x, y, denominator), x * y == 0 ? 0 : (x * y - 1) / denominator + 1);
    }

    function testMulDivUpOverflow(uint256 x, uint256 y, uint256 denominator) public {
        denominator = bound(denominator, 1, type(uint256).max);
        // Overflow if
        //     x * y + denominator - 1 > type(uint256).max
        // <=> x * y > type(uint256).max - denominator + 1
        // <=> y > 0 and x > (type(uint256).max - denominator + 1) / y
        // With
        //     (type(uint256).max - denominator + 1) / y < type(uint256).max
        // <=> y > (type(uint256).max - denominator + 1) / type(uint256).max
        y = bound(y, (type(uint256).max - denominator + 1) / type(uint256).max + 1, type(uint256).max);
        x = bound(x, (type(uint256).max - denominator + 1) / y + 1, type(uint256).max);

        vm.expectRevert();
        MathLib.mulDivUp(x, y, denominator);
    }

    function testMulDivUpUnderverflow(uint256 x, uint256 y) public {
        vm.assume(x > 0 && y > 0);

        vm.expectRevert();
        MathLib.mulDivUp(x, y, 0);
    }

    function testMulDivUpZeroDenominator(uint256 x, uint256 y) public {
        vm.expectRevert();
        MathLib.mulDivUp(x, y, 0);
    }
}
