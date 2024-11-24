// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseMorphoInvariantTest.sol";

contract MorphoStaticInvariantTest is BaseMorphoInvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* INVARIANTS */

    function invariantHealthy() public {
        address[] memory users = targetSenders();

        for (uint256 i; i < allMarketParams.length; ++i) {
            MarketParams memory _marketParams = allMarketParams[i];

            for (uint256 j; j < users.length; ++j) {
                assertTrue(_isHealthy(_marketParams, users[j]));
            }
        }
    }
}
