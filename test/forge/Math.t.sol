// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/FixedPointMathLib.sol";

contract MathTest is Test {
    using FixedPointMathLib for uint256;

    function testWTaylorCompounded(uint256 rate, uint256 timeElapsed) public {
        // Assume rate is less than a ~500% APY. (~180% APR)
        vm.assume(rate < (WAD / 20_000_000) && timeElapsed < 365 days);
        uint256 result = rate.wTaylorCompounded(timeElapsed) + WAD;
        uint256 toCompare = wPow(WAD + rate, timeElapsed);
        assertLe(result, toCompare, "rate should be less than the compounded rate");
        assertGe(result, WAD + timeElapsed * rate, "rate should be greater than the simple interest rate");
        assertLe((toCompare - result) * 100_00 / toCompare, 8_00, "The error should be less than or equal to 8%");
    }

    // Exponentiation by squaring with rounding up.
    function wPow(uint256 x, uint256 n) private pure returns (uint256 z) {
        z = WAD;
        for (; n != 0; n /= 2) {
            z = n % 2 != 0 ? z.mulWadUp(x) : z;
            x = x.mulWadUp(x);
        }
    }
}
