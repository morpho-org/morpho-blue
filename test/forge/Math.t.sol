// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/MathLib.sol";
import "test/forge/helpers/WadMath.sol";

contract MathTest is Test {
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
}
