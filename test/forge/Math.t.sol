// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/MathLib.sol";

contract MathTest is Test {
    using MathLib for uint256;

    function testZeroFloorSub(uint256 x, uint256 y) public {
        uint256 z = x.zeroFloorSub(y);
        assertEq(z, x > y ? x - y : 0);
    }

    function testTaylorSeriesExpansion(uint256 rate, uint256 timeElapsed) public {
        // Assume rate is less than a ~500% annual interest rate.
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        uint256 result = rate.wTaylorSeriesExpansion(timeElapsed) + MathLib.WAD;
        // Add 1000 since rpow can round down
        uint256 toCompare = wPow(MathLib.WAD + rate, timeElapsed);
        // Should be le the true compounded rate.
        assertLe(result, toCompare, "1");
        // Should be ge the simple interest rate.
        assertGe(result, MathLib.WAD + timeElapsed.wMul(rate), "2");
        // Error should be le 8%.
        assertLe((toCompare - result) * 100_00 / toCompare, 8_00, "3");
    }

    function wDivUp(uint256 x, uint256 y) private pure returns (uint256 z) {
        z = (x * y + MathLib.WAD - 1) / MathLib.WAD;
    }

    // Exponentiation by squaring with rounding up.
    function wPow(uint256 x, uint256 n) private pure returns (uint256 z) {
        z = n % 2 != 0 ? x : MathLib.WAD;

        for (n /= 2; n != 0; n /= 2) {
            x = wDivUp(x, x);

            if (n % 2 != 0) {
                z = wDivUp(z, x);
            }
        }
    }
}
