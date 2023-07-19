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
        // Assume rate is less than a ~500% APY. (~180% APR)
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        uint256 result = rate.wTaylorCompounded(timeElapsed, 3) + MathLib.WAD;
        uint256 toCompare = wPow(MathLib.WAD + rate, timeElapsed);
        assertLe(result, toCompare, "rate should be less than the compounded rate");
        assertGe(result, MathLib.WAD + timeElapsed.wMul(rate), "rate should be greater than the simple interest rate");
        assertLe((toCompare - result) * 100_00 / toCompare, 8_00, "The error should be less than or equal to 8%");
    }

    function testTaylorSeriesExpansionGas1(uint256 rate, uint256 timeElapsed) public pure {
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        rate.wTaylorCompounded(timeElapsed, 1);
    }

    function testTaylorSeriesExpansionGas2(uint256 rate, uint256 timeElapsed) public pure {
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        rate.wTaylorCompounded(timeElapsed, 2);
    }

    function testTaylorSeriesExpansionGas3(uint256 rate, uint256 timeElapsed) public pure {
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        rate.wTaylorCompounded(timeElapsed, 3);
    }

    function testTaylorSeriesExpansionGas4(uint256 rate, uint256 timeElapsed) public pure {
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        rate.wTaylorCompounded(timeElapsed, 4);
    }

    function testExponentialGas(uint256 rate, uint256 timeElapsed) public pure {
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        wPow(MathLib.WAD + rate, timeElapsed);
    }

    function testSimpleGas(uint256 rate, uint256 timeElapsed) public pure {
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        timeElapsed * rate;
    }

    function wMulUp(uint256 x, uint256 y) private pure returns (uint256 z) {
        z = (x * y + MathLib.WAD - 1) / MathLib.WAD;
    }

    // Exponentiation by squaring with rounding up.
    function wPow(uint256 x, uint256 n) private pure returns (uint256 z) {
        z = n % 2 != 0 ? x : MathLib.WAD;

        for (n /= 2; n != 0; n /= 2) {
            x = wMulUp(x, x);

            if (n % 2 != 0) {
                z = wMulUp(z, x);
            }
        }
    }
}
