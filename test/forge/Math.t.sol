// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/FixedPointMathLib.sol";

contract MathTest is Test {
    using FixedPointMathLib for uint256;

    function testZeroFloorSub(uint256 x, uint256 y) public {
        uint256 z = x.zeroFloorSub(y);
        assertEq(z, x > y ? x - y : 0);
    }

    function testTaylorSeriesExpansion(uint256 rate, uint256 timeElapsed) public {
        // Assume rate is less than a ~500% APY. (~180% APR)
        vm.assume(rate < (FixedPointMathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        uint256 result = rate.wTaylorCompounded(timeElapsed) + FixedPointMathLib.WAD;
        uint256 toCompare = wPow(FixedPointMathLib.WAD + rate, timeElapsed);
        assertLe(result, toCompare, "rate should be less than the compounded rate");
        assertGe(
            result,
            FixedPointMathLib.WAD + timeElapsed * rate / FixedPointMathLib.WAD,
            "rate should be greater than the simple interest rate"
        );
        assertLe((toCompare - result) * 100_00 / toCompare, 1_00, "The error should be less than or equal to 1%");
    }

    // Exponentiation by squaring with rounding up.
    function wPow(uint256 x, uint256 n) private pure returns (uint256 z) {
        z = n % 2 != 0 ? x : FixedPointMathLib.WAD;

        for (n /= 2; n != 0; n /= 2) {
            x = x.mulWadUp(x);

            if (n % 2 != 0) {
                z = z.mulWadUp(x);
            }
        }
    }
}
