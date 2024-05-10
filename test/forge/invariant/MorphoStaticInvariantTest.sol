// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseMorphoInvariantTest.sol";

contract MorphoStaticInvariantTest is BaseMorphoInvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    function setUp() public virtual override {
        _weightSelector(this.supplyAssetsOnBehalfNoRevert.selector, 12);
        _weightSelector(this.supplySharesOnBehalfNoRevert.selector, 5);
        _weightSelector(this.withdrawAssetsOnBehalfNoRevert.selector, 12);
        _weightSelector(this.borrowAssetsOnBehalfNoRevert.selector, 17);
        _weightSelector(this.repayAssetsOnBehalfNoRevert.selector, 12);
        _weightSelector(this.repaySharesOnBehalfNoRevert.selector, 10);
        _weightSelector(this.supplyCollateralOnBehalfNoRevert.selector, 15);
        _weightSelector(this.withdrawCollateralOnBehalfNoRevert.selector, 10);
        _weightSelector(this.setFeeNoRevert.selector, 2);

        super.setUp();
    }

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
