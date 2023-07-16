// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/MathLib.sol";
import "solmate/utils/FixedPointMathLib.sol";

contract MathTest is Test {
    using MathLib for uint256;

    function testZeroFloorSub(uint256 x, uint256 y) public {
        uint256 z = x.zeroFloorSub(y);
        assertEq(z, x > y ? x - y : 0);
    }

    function testTaylorSeriesExpansion(uint256 rate, uint256 timeElapsed) public {
        // Assume rate is less than a ~500% annual interest rate.
        vm.assume(rate < (MathLib.WAD / 20_000_000) && timeElapsed < 365 days);
        uint256 result = rate.taylorSeriesExpansion(timeElapsed) + MathLib.WAD;
        uint256 toCompare = FixedPointMathLib.rpow(MathLib.WAD + rate, timeElapsed, MathLib.WAD);
        // For a three term expansion, the error should be less than 12% for a 500% interest rate for one year)
        assertLe(result, toCompare);
        assertLe((toCompare - result) * 100_00 / toCompare, 12_00);
    }
}
