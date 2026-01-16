// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import {TieredLiquidationMorpho} from "../../../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../../../src/extensions/WhitelistRegistry.sol";
import {MarketParams, Position} from "../../../src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../../src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../../src/libraries/SharesMathLib.sol";

/// @title TwoStepLiquidationTest
/// @notice Tests for Sui-style two-step liquidation (full debt repayment)
contract TwoStepLiquidationTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    TieredLiquidationMorpho public tieredMorpho;
    WhitelistRegistry public whitelistRegistry;
    
    address public liquidator = address(0x123);
    address public borrower = address(0x456);

    function setUp() public override {
        super.setUp();

        whitelistRegistry = new WhitelistRegistry(address(this));
        tieredMorpho = new TieredLiquidationMorpho(address(morpho), address(whitelistRegistry));

        // Configure market with 10% liquidation bonus, no cooldown, no min seized, no whitelist
        tieredMorpho.configureMarket(id, true, 0.1e18, WAD, 0, 0, false);

        // Setup whitelist
        whitelistRegistry.initializeMarket(id, address(this));
        whitelistRegistry.addLiquidator(id, liquidator);
        whitelistRegistry.setWhitelistMode(id, true);
    }

    function _setupBorrowerPosition(uint256 collateralAmount, uint256 borrowAmount) internal {
        loanToken.setBalance(SUPPLIER, 100 ether);
        vm.startPrank(SUPPLIER);
        loanToken.approve(address(morpho), type(uint256).max);
        morpho.supply(marketParams, 100 ether, 0, SUPPLIER, "");
        vm.stopPrank();

        collateralToken.setBalance(borrower, collateralAmount);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams, collateralAmount, borrower, "");
        morpho.borrow(marketParams, borrowAmount, 0, borrower, borrower);
        vm.stopPrank();
    }

    function testRequestLiquidationFullDebt() public {
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7 ether;

        _setupBorrowerPosition(collateralAmount, borrowAmount);
        oracle.setPrice(ORACLE_PRICE_SCALE * 85 / 100);

        loanToken.setBalance(liquidator, 20 ether);

        vm.startPrank(liquidator);
        loanToken.approve(address(tieredMorpho), type(uint256).max);
        (uint256 seized, uint256 repaid) = tieredMorpho.requestLiquidation(marketParams, borrower, 0.5e18);
        vm.stopPrank();

        // Verify amounts (50% ratio means 50% of debt)
        assertGt(repaid, 0, "Should repay debt");
        assertGt(seized, 0, "Should seize collateral");
        
        // With 50% liquidation ratio
        assertApproxEqRel(repaid, borrowAmount / 2, 0.1e18, "Should repay ~50% of debt");
    }

    function testCompleteLiquidation() public {
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7 ether;

        _setupBorrowerPosition(collateralAmount, borrowAmount);
        oracle.setPrice(ORACLE_PRICE_SCALE * 85 / 100);

        loanToken.setBalance(liquidator, 20 ether);

        vm.startPrank(liquidator);
        loanToken.approve(address(tieredMorpho), type(uint256).max);
        tieredMorpho.requestLiquidation(marketParams, borrower, 0.5e18);
        
        tieredMorpho.completeLiquidation(marketParams, borrower);
        vm.stopPrank();

        assertEq(
            uint256(tieredMorpho.liquidationStatus(id, borrower)),
            uint256(TieredLiquidationMorpho.LiquidationStatus.Completed),
            "Should be completed"
        );
    }
}
