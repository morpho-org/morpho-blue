// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../lib/forge-std/src/Test.sol";
import "../../../lib/forge-std/src/console.sol";

import "./PreLiquidationBaseTest.sol";

import {
    IPreLiquidation,
    PreLiquidationParams
} from "../../../src/periphery/pre-liquidation/interfaces/IPreLiquidation.sol";
import {IPreLiquidationCallback} from "../../../src/periphery/pre-liquidation/interfaces/IPreLiquidationCallback.sol";
import {IOracle} from "../../../src/interfaces/IOracle.sol";
import {IMorphoRepayCallback} from "../../../src/interfaces/IMorphoCallbacks.sol";
import {PreLiquidation} from "../../../src/periphery/pre-liquidation/PreLiquidation.sol";
import {PreLiquidationFactory} from "../../../src/periphery/pre-liquidation/PreLiquidationFactory.sol";
import "../../../src/interfaces/IMorpho.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {ErrorsLib} from "../../../src/periphery/pre-liquidation/libraries/ErrorsLib.sol";
import {MarketParamsLib} from "../../../src/libraries/MarketParamsLib.sol";
import {MathLib, WAD} from "../../../src/libraries/MathLib.sol";
import {SharesMathLib} from "../../../src/libraries/SharesMathLib.sol";

contract PreLiquidationTest is PreLiquidationBaseTest, IPreLiquidationCallback {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using MathLib for uint256;

    event CallbackReached();

    function setUp() public override {
        super.setUp();

        factory = new PreLiquidationFactory(address(MORPHO));
    }

    function testPreLiquidationLiquidatable(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 newPrice
    ) public virtual {
        preLiquidationParams = boundPreLiquidationParameters({
            preLiquidationParams: preLiquidationParams,
            minPreLltv: WAD / 2,
            maxPreLltv: marketParams.lltv - 1,
            minPreLCF: WAD / 100,
            maxPreLCF: WAD,
            minPreLIF: WAD,
            maxPreLIF: WAD.wDivDown(lltv),
            preLiqOracle: marketParams.oracle
        });

        collateralAmount = bound(collateralAmount, minCollateral, maxCollateral);
        (uint256 collateralQuoted, uint256 borrowPreLiquidationThreshold, uint256 borrowLiquidationThreshold) =
            _getBorrowBounds(preLiquidationParams, marketParams, collateralAmount);
        borrowAmount = bound(borrowAmount, borrowPreLiquidationThreshold + 1, borrowLiquidationThreshold);

        _preparePreLiquidation(preLiquidationParams, collateralAmount, borrowAmount, LIQUIDATOR);

        uint256 ltv = borrowAmount.wDivUp(collateralQuoted);
        uint256 prevPrice = oracle.price();
        newPrice = bound(newPrice, prevPrice / 10, prevPrice.wDivDown(marketParams.lltv).wMulDown(ltv));
        oracle.setPrice(newPrice);

        uint256 newLtv = borrowAmount.wDivUp(collateralAmount.mulDivDown(newPrice, ORACLE_PRICE_SCALE));
        vm.assume(newLtv > marketParams.lltv);

        vm.startPrank(LIQUIDATOR);
        Position memory position = MORPHO.position(id, BORROWER);

        uint256 closeFactor = _closeFactor(preLiquidationParams, newLtv);
        uint256 repayableShares = uint256(position.borrowShares).wMulDown(closeFactor);

        vm.expectRevert(ErrorsLib.LiquidatablePosition.selector);
        preLiquidation.preLiquidate(BORROWER, 0, repayableShares, hex"");
    }

    function testPreLiquidationShares(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) public virtual {
        preLiquidationParams = boundPreLiquidationParameters({
            preLiquidationParams: preLiquidationParams,
            minPreLltv: WAD / 100,
            maxPreLltv: marketParams.lltv - 1,
            minPreLCF: WAD / 100,
            maxPreLCF: WAD,
            minPreLIF: WAD,
            maxPreLIF: WAD.wDivDown(lltv),
            preLiqOracle: marketParams.oracle
        });

        collateralAmount = bound(collateralAmount, minCollateral, maxCollateral);
        (uint256 collateralQuoted, uint256 borrowPreLiquidationThreshold, uint256 borrowLiquidationThreshold) =
            _getBorrowBounds(preLiquidationParams, marketParams, collateralAmount);
        borrowAmount = bound(borrowAmount, borrowPreLiquidationThreshold + 1, borrowLiquidationThreshold);

        _preparePreLiquidation(preLiquidationParams, collateralAmount, borrowAmount, LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        Position memory position = MORPHO.position(id, BORROWER);

        uint256 ltv = borrowAmount.wDivUp(collateralQuoted);
        uint256 closeFactor = _closeFactor(preLiquidationParams, ltv);
        uint256 repayableShares = uint256(position.borrowShares).wMulDown(closeFactor);

        uint256 liquidatorCollatBefore = collateralToken.balanceOf(LIQUIDATOR);
        uint256 liquidatorLoanBefore = loanToken.balanceOf(LIQUIDATOR);

        (uint256 seizedAssets, uint256 repaidAssets) = preLiquidation.preLiquidate(BORROWER, 0, repayableShares, hex"");

        uint256 liquidatorCollatAfter = collateralToken.balanceOf(LIQUIDATOR);
        uint256 liquidatorLoanAfter = loanToken.balanceOf(LIQUIDATOR);

        assertEq(liquidatorCollatAfter - liquidatorCollatBefore, seizedAssets);
        assertEq(liquidatorLoanBefore - liquidatorLoanAfter, repaidAssets);
    }

    function testPreLiquidationAssets(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) public virtual {
        preLiquidationParams = boundPreLiquidationParameters({
            preLiquidationParams: preLiquidationParams,
            minPreLltv: WAD / 100,
            maxPreLltv: marketParams.lltv - 1,
            minPreLCF: WAD / 100,
            maxPreLCF: WAD,
            minPreLIF: WAD,
            maxPreLIF: WAD.wDivDown(lltv),
            preLiqOracle: marketParams.oracle
        });

        collateralAmount = bound(collateralAmount, minCollateral, maxCollateral);
        (uint256 collateralQuoted, uint256 borrowPreLiquidationThreshold, uint256 borrowLiquidationThreshold) =
            _getBorrowBounds(preLiquidationParams, marketParams, collateralAmount);
        borrowAmount = bound(borrowAmount, borrowPreLiquidationThreshold + 1, borrowLiquidationThreshold);
        _preparePreLiquidation(preLiquidationParams, collateralAmount, borrowAmount, LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        Position memory position = MORPHO.position(id, BORROWER);
        Market memory m = MORPHO.market(id);

        uint256 ltv = borrowAmount.wDivUp(collateralQuoted);
        uint256 closeFactor = _closeFactor(preLiquidationParams, ltv);
        uint256 preLIF = _preLIF(preLiquidationParams, ltv);

        uint256 collateralPrice = IOracle(preLiquidationParams.preLiquidationOracle).price();
        uint256 repayableShares = uint256(position.borrowShares).wMulDown(closeFactor);
        uint256 seizabledAssets = repayableShares.toAssetsDown(m.totalBorrowAssets, m.totalBorrowShares)
            .wMulDown(preLIF)
            .mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);

        uint256 liquidatorCollatBefore = collateralToken.balanceOf(LIQUIDATOR);
        uint256 liquidatorLoanBefore = loanToken.balanceOf(LIQUIDATOR);

        (uint256 seizedAssets, uint256 repaidAssets) = preLiquidation.preLiquidate(BORROWER, seizabledAssets, 0, hex"");

        uint256 liquidatorCollatAfter = collateralToken.balanceOf(LIQUIDATOR);
        uint256 liquidatorLoanAfter = loanToken.balanceOf(LIQUIDATOR);

        assertEq(liquidatorCollatAfter - liquidatorCollatBefore, seizedAssets);
        assertEq(liquidatorLoanBefore - liquidatorLoanAfter, repaidAssets);
    }

    function testPreLiquidationCallback(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) public virtual {
        preLiquidationParams = boundPreLiquidationParameters({
            preLiquidationParams: preLiquidationParams,
            minPreLltv: WAD / 100,
            maxPreLltv: marketParams.lltv - 1,
            minPreLCF: WAD / 100,
            maxPreLCF: WAD,
            minPreLIF: WAD,
            maxPreLIF: WAD.wDivDown(lltv),
            preLiqOracle: marketParams.oracle
        });

        collateralAmount = bound(collateralAmount, minCollateral, maxCollateral);
        (uint256 collateralQuoted, uint256 borrowPreLiquidationThreshold, uint256 borrowLiquidationThreshold) =
            _getBorrowBounds(preLiquidationParams, marketParams, collateralAmount);
        borrowAmount = bound(borrowAmount, borrowPreLiquidationThreshold + 1, borrowLiquidationThreshold);

        _preparePreLiquidation(preLiquidationParams, collateralAmount, borrowAmount, address(this));

        Position memory position = MORPHO.position(marketParams.id(), BORROWER);

        uint256 ltv = borrowAmount.wDivUp(collateralQuoted);
        uint256 closeFactor = _closeFactor(preLiquidationParams, ltv);
        uint256 repayableShares = uint256(position.borrowShares).wMulDown(closeFactor);

        bytes memory data = abi.encode(this.testPreLiquidationCallback.selector, hex"");

        vm.recordLogs();
        preLiquidation.preLiquidate(BORROWER, 0, repayableShares, data);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assert(entries.length == 7);
        assert(entries[3].topics[0] == keccak256("CallbackReached()"));
    }

    function onPreLiquidate(uint256, bytes memory data) external {
        bytes4 selector;
        (selector,) = abi.decode(data, (bytes4, bytes));
        require(selector == this.testPreLiquidationCallback.selector);

        emit CallbackReached();
    }

    function testPreLiquidationWithInterest(PreLiquidationParams memory preLiquidationParams, uint256 collateralAmount)
        public
    {
        preLiquidationParams = boundPreLiquidationParameters({
            preLiquidationParams: preLiquidationParams,
            minPreLltv: WAD / 100,
            maxPreLltv: marketParams.lltv - 1,
            minPreLCF: WAD / 100,
            maxPreLCF: WAD,
            minPreLIF: WAD,
            maxPreLIF: WAD.wDivDown(lltv),
            preLiqOracle: marketParams.oracle
        });

        collateralAmount = bound(collateralAmount, minCollateral, maxCollateral);

        (uint256 collateralQuoted, uint256 borrowPreLiquidationThreshold,) =
            _getBorrowBounds(preLiquidationParams, marketParams, collateralAmount);
        _preparePreLiquidation(preLiquidationParams, collateralAmount, borrowPreLiquidationThreshold - 1, LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);

        vm.expectRevert(ErrorsLib.NotPreLiquidatablePosition.selector);
        preLiquidation.preLiquidate(BORROWER, 0, 1, hex"");

        vm.warp(block.timestamp + 12);
        vm.roll(block.number + 1);

        MORPHO.accrueInterest(marketParams);
        Position memory position = MORPHO.position(id, BORROWER);
        Market memory m = MORPHO.market(id);

        uint256 borrowAmount = uint256(position.borrowShares).toAssetsUp(m.totalBorrowAssets, m.totalBorrowShares);
        uint256 ltv = borrowAmount.wDivUp(collateralQuoted);
        vm.assume(ltv >= preLiquidationParams.preLltv);
        vm.assume(ltv <= marketParams.lltv);

        uint256 closeFactor = _closeFactor(preLiquidationParams, ltv);
        uint256 repayableShares = uint256(position.borrowShares).wMulDown(closeFactor);

        preLiquidation.preLiquidate(BORROWER, 0, repayableShares, hex"");
    }

    function testOracle(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) public virtual {
        OracleMock customOracle = new OracleMock();
        customOracle.setPrice(2 * IOracle(marketParams.oracle).price());

        preLiquidationParams = boundPreLiquidationParameters({
            preLiquidationParams: preLiquidationParams,
            minPreLltv: WAD / 100,
            maxPreLltv: marketParams.lltv - 1,
            minPreLCF: WAD / 100,
            maxPreLCF: WAD,
            minPreLIF: WAD,
            maxPreLIF: WAD.wDivDown(lltv),
            preLiqOracle: address(customOracle)
        });

        collateralAmount = bound(collateralAmount, minCollateral, maxCollateral);

        uint256 collateralMarketOraclePrice = IOracle(marketParams.oracle).price();
        uint256 borrowMarketOracleThreshold = uint256(collateralAmount)
            .mulDivDown(collateralMarketOraclePrice, ORACLE_PRICE_SCALE)
            .wMulDown(preLiquidationParams.preLltv);
        (, uint256 borrowPreLiquidationThreshold,) =
            _getBorrowBounds(preLiquidationParams, marketParams, collateralAmount);

        uint256 maxBorrow = uint256(collateralAmount)
            .mulDivDown(collateralMarketOraclePrice, ORACLE_PRICE_SCALE)
            .wMulDown(marketParams.lltv);
        borrowAmount = bound(borrowAmount, borrowMarketOracleThreshold, borrowPreLiquidationThreshold - 1);
        borrowAmount = bound(borrowAmount, borrowMarketOracleThreshold, maxBorrow - 1);

        _preparePreLiquidation(preLiquidationParams, collateralAmount, borrowAmount, LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);

        vm.expectRevert(ErrorsLib.NotPreLiquidatablePosition.selector);
        preLiquidation.preLiquidate(BORROWER, 0, 1, hex"");
    }
}
