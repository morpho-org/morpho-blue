// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../src/periphery/adaptive-curve-irm/AdaptiveCurveIrm.sol";
import "../../../src/periphery/adaptive-curve-irm/libraries/AdaptiveCurveIrmLib.sol";
import "../../../src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../../src/libraries/periphery/MorphoBalancesLib.sol";

import "../../../lib/forge-std/src/Test.sol";

contract AdaptiveCurveIrmLibTest is Test {
    using MarketParamsLib for MarketParams;
    using stdStorage for StdStorage;
    using MathLib for uint256;

    address public adaptiveCurveIrm;

    function setUp() public {
        adaptiveCurveIrm = address(new AdaptiveCurveIrm(address(this)));
    }

    function testExpectedMarketBalances(
        uint256 rateAtTarget,
        uint128 initTotalSupplyAssets,
        uint128 initTotalBorrowAssets,
        uint128 initTotalSupplyShares,
        uint128 initTotalBorrowShares,
        uint128 lastUpdate,
        uint128 fee
    ) public {
        vm.warp(1000 days);
        rateAtTarget = bound(rateAtTarget, 0, uint256(ConstantsLib.MAX_RATE_AT_TARGET));
        initTotalSupplyAssets = uint128(bound(initTotalSupplyAssets, 0, 1e35));
        initTotalBorrowAssets = uint128(bound(initTotalBorrowAssets, 0, initTotalSupplyAssets));
        initTotalSupplyShares = uint128(bound(initTotalSupplyShares, 0, 1e35));
        initTotalBorrowShares = uint128(bound(initTotalBorrowShares, 0, 1e35));
        lastUpdate = uint128(bound(lastUpdate, 0, 1000 days));
        fee = uint128(bound(fee, 0, 0.25e18));

        Market memory market = Market({
            totalSupplyAssets: initTotalSupplyAssets,
            totalSupplyShares: initTotalSupplyShares,
            totalBorrowAssets: initTotalBorrowAssets,
            totalBorrowShares: initTotalBorrowShares,
            lastUpdate: lastUpdate,
            fee: fee
        });

        MarketParams memory marketParams = MarketParams({
            loanToken: address(0), collateralToken: address(0), oracle: address(0), irm: adaptiveCurveIrm, lltv: 0
        });
        bytes32 id = Id.unwrap(marketParams.id());

        address morpho = makeAddr("morpho");
        // set rate at target.
        bytes32 slot = keccak256(abi.encode(id, 0));
        vm.store(adaptiveCurveIrm, slot, bytes32(rateAtTarget));
        assertEq(IAdaptiveCurveIrm(adaptiveCurveIrm).rateAtTarget(Id.wrap(id)), int256(rateAtTarget), "rateAtTarget");
        // set market state.
        vm.mockCall(morpho, abi.encodeWithSelector(IMorpho.market.selector), abi.encode(market));

        this.adaptiveCurveIrm();
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets, uint256 totalBorrowShares) =
            AdaptiveCurveIrmLib.expectedMarketBalances(morpho, id, adaptiveCurveIrm);
        this.adaptiveCurveIrm();
        (
            uint256 expectedTotalSupplyAssets,
            uint256 expectedTotalSupplyShares,
            uint256 expectedTotalBorrowAssets,
            uint256 expectedTotalBorrowShares
        ) = MorphoBalancesLib.expectedMarketBalances(IMorpho(morpho), marketParams);

        assertEq(totalSupplyAssets, expectedTotalSupplyAssets, "total supply assets");
        assertEq(totalSupplyShares, expectedTotalSupplyShares, "total supply shares");
        assertEq(totalBorrowAssets, expectedTotalBorrowAssets, "total borrow assets");
        assertEq(totalBorrowShares, expectedTotalBorrowShares, "total borrow shares");
    }

    function testBorrowRateView(uint256 rateAtTarget, Market memory market) public {
        vm.warp(1000 days);

        rateAtTarget = bound(rateAtTarget, 0, uint256(ConstantsLib.MAX_RATE_AT_TARGET));
        // borrow rate doesn't revert on utilization > 1, and the test passes. Still, we require that.
        market.totalBorrowAssets = uint128(bound(market.totalBorrowAssets, 0, market.totalSupplyAssets));
        market.lastUpdate = uint128(bound(market.lastUpdate, 0, 1000 days));
        market.fee = uint128(bound(market.fee, 0, 0.25e18));

        MarketParams memory marketParams;
        marketParams.irm = adaptiveCurveIrm;
        bytes32 id = Id.unwrap(marketParams.id());

        // set rate at target.
        // compute slot by hand.
        bytes32 slot = keccak256(abi.encode(id, 0));
        vm.store(adaptiveCurveIrm, slot, bytes32(rateAtTarget));
        assertEq(IAdaptiveCurveIrm(adaptiveCurveIrm).rateAtTarget(Id.wrap(id)), int256(rateAtTarget), "rateAtTarget");

        uint256 computedBorrowRate = AdaptiveCurveIrmLib.borrowRateView(id, market, adaptiveCurveIrm);
        uint256 expectedBorrowRate = IAdaptiveCurveIrm(adaptiveCurveIrm).borrowRateView(marketParams, market);
        assertEq(computedBorrowRate, expectedBorrowRate, "computedBorrowRate");
    }
}
