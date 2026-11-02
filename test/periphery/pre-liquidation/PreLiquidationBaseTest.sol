// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../lib/forge-std/src/Test.sol";
import "../../../lib/forge-std/src/console2.sol";

import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol";
import {IrmMock} from "../../../src/mocks/IrmMock.sol";
import {OracleMock} from "../../../src/mocks/OracleMock.sol";

import {MarketParams, IMorpho, Id} from "../../../src/interfaces/IMorpho.sol";
import {IOracle} from "../../../src/interfaces/IOracle.sol";
import {MarketParamsLib} from "../../../src/libraries/MarketParamsLib.sol";
import {ORACLE_PRICE_SCALE} from "../../../src/libraries/ConstantsLib.sol";
import {WAD, MathLib} from "../../../src/libraries/MathLib.sol";
import {UtilsLib} from "../../../src/libraries/UtilsLib.sol";

import {
    PreLiquidationParams,
    IPreLiquidation
} from "../../../src/periphery/pre-liquidation/interfaces/IPreLiquidation.sol";
import {PreLiquidationFactory} from "../../../src/periphery/pre-liquidation/PreLiquidationFactory.sol";

contract PreLiquidationBaseTest is Test {
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;

    address internal SUPPLIER = makeAddr("Supplier");
    address internal BORROWER = makeAddr("Borrower");
    address internal LIQUIDATOR = makeAddr("Liquidator");
    address internal MORPHO_OWNER = makeAddr("MorphoOwner");
    address internal MORPHO_FEE_RECIPIENT = makeAddr("MorphoFeeRecipient");

    IMorpho internal MORPHO = IMorpho(deployCode("Morpho.sol", abi.encode(MORPHO_OWNER)));
    ERC20Mock internal loanToken = new ERC20Mock();
    ERC20Mock internal collateralToken = new ERC20Mock();
    OracleMock internal oracle = new OracleMock();
    IrmMock internal irm = new IrmMock();
    uint256 internal lltv = 0.8 ether; // 80%

    MarketParams internal marketParams;
    Id internal id;

    uint256 internal minCollateral = 10 ** 18;
    uint256 internal maxCollateral = 10 ** 24;

    PreLiquidationFactory internal factory;
    IPreLiquidation internal preLiquidation;

    function setUp() public virtual {
        vm.label(address(MORPHO), "Morpho");
        vm.label(address(loanToken), "Loan");
        vm.label(address(collateralToken), "Collateral");
        vm.label(address(oracle), "Oracle");
        vm.label(address(irm), "Irm");

        oracle.setPrice(ORACLE_PRICE_SCALE);

        vm.startPrank(MORPHO_OWNER);
        MORPHO.enableIrm(address(irm));
        MORPHO.setFeeRecipient(MORPHO_FEE_RECIPIENT);

        MORPHO.enableLltv(lltv);
        vm.stopPrank();

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: lltv
        });
        id = marketParams.id();

        MORPHO.createMarket(marketParams);

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(MORPHO), type(uint256).max);
        vm.stopPrank();

        vm.prank(BORROWER);
        collateralToken.approve(address(MORPHO), type(uint256).max);
    }

    function boundPreLiquidationParameters(
        PreLiquidationParams memory preLiquidationParams,
        uint256 minPreLltv,
        uint256 maxPreLltv,
        uint256 minPreLCF,
        uint256 maxPreLCF,
        uint256 minPreLIF,
        uint256 maxPreLIF,
        address preLiqOracle
    ) internal pure returns (PreLiquidationParams memory) {
        preLiquidationParams.preLltv = bound(preLiquidationParams.preLltv, minPreLltv, maxPreLltv);
        preLiquidationParams.preLCF1 = bound(preLiquidationParams.preLCF1, minPreLCF, maxPreLCF);
        preLiquidationParams.preLCF2 = bound(preLiquidationParams.preLCF2, preLiquidationParams.preLCF1, maxPreLCF);
        preLiquidationParams.preLIF1 = bound(preLiquidationParams.preLIF1, minPreLIF, maxPreLIF);
        preLiquidationParams.preLIF2 = bound(preLiquidationParams.preLIF2, preLiquidationParams.preLIF1, maxPreLIF);
        preLiquidationParams.preLiquidationOracle = preLiqOracle;

        return preLiquidationParams;
    }

    function _preparePreLiquidation(
        PreLiquidationParams memory preLiquidationParams,
        uint256 collateralAmount,
        uint256 borrowAmount,
        address liquidator
    ) internal {
        preLiquidation = factory.createPreLiquidation(id, preLiquidationParams);

        loanToken.setBalance(SUPPLIER, loanToken.balanceOf(SUPPLIER) + borrowAmount);
        vm.prank(SUPPLIER);
        if (borrowAmount > 0) {
            MORPHO.supply(marketParams, borrowAmount, 0, SUPPLIER, hex"");
        }

        collateralToken.setBalance(BORROWER, collateralToken.balanceOf(BORROWER) + collateralAmount);
        vm.startPrank(BORROWER);

        MORPHO.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

        if (borrowAmount > 0) {
            MORPHO.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        }
        MORPHO.setAuthorization(address(preLiquidation), true);
        vm.stopPrank();

        loanToken.setBalance(liquidator, loanToken.balanceOf(liquidator) + type(uint128).max);
        vm.prank(liquidator);
        loanToken.approve(address(preLiquidation), type(uint256).max);
    }

    function _closeFactor(PreLiquidationParams memory preLiquidationParams, uint256 ltv)
        internal
        view
        returns (uint256)
    {
        return (ltv - preLiquidationParams.preLltv)
                .wDivDown(marketParams.lltv - preLiquidationParams.preLltv)
                .wMulDown(preLiquidationParams.preLCF2 - preLiquidationParams.preLCF1) + preLiquidationParams.preLCF1;
    }

    function _preLIF(PreLiquidationParams memory preLiquidationParams, uint256 ltv) internal view returns (uint256) {
        return (ltv - preLiquidationParams.preLltv)
                .wDivDown(marketParams.lltv - preLiquidationParams.preLltv)
                .wMulDown(preLiquidationParams.preLIF2 - preLiquidationParams.preLIF1) + preLiquidationParams.preLIF1;
    }

    function _getBorrowBounds(
        PreLiquidationParams memory preLiquidationParams,
        MarketParams memory _marketParams,
        uint256 collateralAmount
    ) internal view returns (uint256, uint256, uint256) {
        uint256 collateralPrice = IOracle(preLiquidationParams.preLiquidationOracle).price();
        uint256 collateralQuoted = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        uint256 borrowPreLiquidationThreshold = collateralQuoted.wMulDown(preLiquidationParams.preLltv);
        uint256 borrowLiquidationThreshold = collateralQuoted.wMulDown(_marketParams.lltv);

        return (collateralQuoted, borrowPreLiquidationThreshold, borrowLiquidationThreshold);
    }
}
