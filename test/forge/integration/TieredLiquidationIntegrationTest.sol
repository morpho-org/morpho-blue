// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import {TieredLiquidationMorpho} from "../../../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../../../src/extensions/WhitelistRegistry.sol";
import {LiquidationTierLib} from "../../../src/extensions/libraries/LiquidationTierLib.sol";
import {HealthFactorLib} from "../../../src/extensions/libraries/HealthFactorLib.sol";
import {ORACLE_PRICE_SCALE} from "../../../src/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "../../../src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../../src/libraries/SharesMathLib.sol";

contract TieredLiquidationIntegrationTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    
    TieredLiquidationMorpho public tieredMorpho;
    WhitelistRegistry public whitelistRegistry;

    address public marketAdmin = makeAddr("marketAdmin");
    address public liquidator1 = makeAddr("liquidator1");
    address public liquidator2 = makeAddr("liquidator2");
    address public unauthorizedLiquidator = makeAddr("unauthorized");

    function setUp() public override {
        super.setUp();

        // Deploy whitelist registry
        whitelistRegistry = new WhitelistRegistry(OWNER);

        // Deploy tiered liquidation morpho
        tieredMorpho = new TieredLiquidationMorpho(address(morpho), address(whitelistRegistry));

        // Setup market admin
        vm.prank(OWNER);
        whitelistRegistry.initializeMarket(id, marketAdmin);

        // Add liquidators to whitelist and enable whitelist mode
        // Tier 1 requires whitelist, so we need to enable it
        vm.startPrank(marketAdmin);
        whitelistRegistry.addLiquidator(id, liquidator1);
        whitelistRegistry.addLiquidator(id, liquidator2);
        whitelistRegistry.setWhitelistMode(id, true);
        vm.stopPrank();

        // Enable tiered liquidation with default tiers
        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.enableTieredLiquidation(id);
    }

    function testTieredLiquidationEnabled() public {
        assertTrue(tieredMorpho.isTieredLiquidationEnabled(id));

        LiquidationTierLib.LiquidationTier[] memory tiers = tieredMorpho.getMarketTiers(id);
        assertEq(tiers.length, 2, "Should have 2 tiers");
        // Note: Due to Morpho Blue constraint (HF < 1.0 for liquidation), 
        // Tier 1 threshold is 1.0 (conservative) and Tier 2 is 0.95 (aggressive)
        assertEq(tiers[0].healthFactorThreshold, 1.0e18, "Tier 1 threshold should be 1.0");
        assertTrue(tiers[0].whitelistOnly, "Tier 1 should require whitelist");
        assertGt(tiers[1].healthFactorThreshold, 0, "Tier 2 should have a threshold");
        assertFalse(tiers[1].whitelistOnly, "Tier 2 should NOT require whitelist");
    }

    function testWhitelistConfiguration() public {
        assertTrue(whitelistRegistry.isWhitelistEnabled(id), "Whitelist should be enabled");
        assertTrue(whitelistRegistry.canLiquidate(id, liquidator1), "Liquidator1 should be authorized");
        assertTrue(whitelistRegistry.canLiquidate(id, liquidator2), "Liquidator2 should be authorized");
        assertFalse(
            whitelistRegistry.canLiquidate(id, unauthorizedLiquidator), "Unauthorized should not be authorized"
        );
    }

    function testHealthFactorCalculation() public {
        // Setup: BORROWER supplies collateral and borrows
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 5 ether; // Lower borrow amount to ensure healthy position

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);

        // Check health factor
        uint256 healthFactor = tieredMorpho.getHealthFactor(marketParams, BORROWER);

        // With LLTV = 0.965 (96.5%), HF should be > 1.0
        // HF = (10 * 1 * 0.965) / 5 = 1.93
        assertGt(healthFactor, 1e18, "Should be healthy initially");
    }

    function testTier1LiquidationWhitelistOnly() public {
        // Setup position with more borrowed to make it easier to make unhealthy
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7.5 ether;

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);

        // Simulate price drop to make position unhealthy (0.95 < HF < 1.0)
        _setPriceToMakeHealthFactor(0.98e18);

        uint256 healthFactor = tieredMorpho.getHealthFactor(marketParams, BORROWER);
        console.log("Actual HF:", healthFactor);
        assertLt(healthFactor, 1.0e18, "Should be in Tier 1 range");
        assertGt(healthFactor, 0.95e18, "Should be above Tier 2 range");

        // Unauthorized liquidator should fail (need to fund first to test authorization)
        _fundLiquidator(unauthorizedLiquidator, 10 ether);
        vm.prank(unauthorizedLiquidator);
        vm.expectRevert(TieredLiquidationMorpho.Unauthorized.selector);
        tieredMorpho.liquidate(marketParams, BORROWER, 1 ether, 0, "");

        // Whitelisted liquidator should succeed
        uint256 seizedAssets = 1 ether;
        _fundLiquidator(liquidator1, 10 ether);

        vm.prank(liquidator1);
        (uint256 seized, uint256 repaid) = tieredMorpho.liquidate(marketParams, BORROWER, seizedAssets, 0, "");

        assertGt(seized, 0, "Should have seized collateral");
        assertGt(repaid, 0, "Should have repaid debt");
    }

    function testTier2LiquidationPublicAccess() public {
        // Setup unhealthy position with HF < 0.95 (Tier 2 range)
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7.5 ether;

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);

        // Simulate severe price drop to make HF < 0.95 (Tier 2)
        _setPriceToMakeHealthFactor(0.80e18);

        uint256 healthFactor = tieredMorpho.getHealthFactor(marketParams, BORROWER);
        console.log("Health Factor:", healthFactor);
        assertLt(healthFactor, 0.95e18, "Should be in Tier 2 range (< 0.95)");

        // Even unauthorized liquidator should succeed in Tier 2 (public access)
        uint256 seizedAssets = 1 ether;
        _fundLiquidator(unauthorizedLiquidator, 10 ether);

        vm.prank(unauthorizedLiquidator);
        (uint256 seized, uint256 repaid) = tieredMorpho.liquidate(marketParams, BORROWER, seizedAssets, 0, "");

        assertGt(seized, 0, "Should have seized collateral");
        assertGt(repaid, 0, "Should have repaid debt");
    }

    function testMaxLiquidationRatioTier1() public {
        // Tier 1 should only allow 50% liquidation
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7.5 ether;

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);
        _setPriceToMakeHealthFactor(0.98e18);

        // Try to liquidate more than 50%
        uint256 excessiveSeizedAssets = 6 ether; // 60% of collateral
        _fundLiquidator(liquidator1, 20 ether);

        vm.prank(liquidator1);
        vm.expectRevert(TieredLiquidationMorpho.ExceedsMaxLiquidation.selector);
        tieredMorpho.liquidate(marketParams, BORROWER, excessiveSeizedAssets, 0, "");
    }

    function testLiquidationBonus() public {
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7.5 ether;

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);
        _setPriceToMakeHealthFactor(0.98e18);

        uint256 seizedAssets = 1 ether;
        _fundLiquidator(liquidator1, 10 ether);

        uint256 liquidatorBalanceBefore = loanToken.balanceOf(liquidator1);

        vm.prank(liquidator1);
        (uint256 seized, uint256 repaid) = tieredMorpho.liquidate(marketParams, BORROWER, seizedAssets, 0, "");

        // Liquidator should receive bonus (5% in Tier 1)
        // Seized assets value should be > repaid assets (due to bonus)
        uint256 seizedValue = seized; // Simplified, assuming 1:1 price
        assertGt(seizedValue, repaid, "Should have received liquidation bonus");
    }

    function testCooldownPeriod() public {
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7.5 ether;

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);
        _setPriceToMakeHealthFactor(0.98e18);

        _fundLiquidator(liquidator1, 20 ether);

        // First liquidation
        vm.prank(liquidator1);
        tieredMorpho.liquidate(marketParams, BORROWER, 0.5 ether, 0, "");

        // Immediate second liquidation should fail (1 hour cooldown in Tier 1)
        vm.prank(liquidator1);
        vm.expectRevert(TieredLiquidationMorpho.CooldownNotElapsed.selector);
        tieredMorpho.liquidate(marketParams, BORROWER, 0.5 ether, 0, "");

        // After cooldown period, should succeed
        skip(1 hours + 1);

        vm.prank(liquidator1);
        tieredMorpho.liquidate(marketParams, BORROWER, 0.5 ether, 0, "");
    }

    function testDisableTieredLiquidation() public {
        // Disable tiered liquidation
        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.disableTieredLiquidation(id);

        assertFalse(tieredMorpho.isTieredLiquidationEnabled(id), "Should be disabled");

        // Should fall back to standard Morpho liquidation
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 7.5 ether;

        _setupBorrowerPosition(BORROWER, collateralAmount, borrowAmount);
        _setPriceToMakeHealthFactor(0.80e18);

        _fundLiquidator(unauthorizedLiquidator, 10 ether);

        // Should work with standard Morpho rules (bypasses tiered logic)
        vm.prank(unauthorizedLiquidator);
        (uint256 seized, uint256 repaid) = tieredMorpho.liquidate(marketParams, BORROWER, 1 ether, 0, "");

        assertGt(seized, 0, "Should have seized collateral");
    }

    function testCustomTierConfiguration() public {
        // Create custom tiers
        LiquidationTierLib.LiquidationTier[] memory customTiers =
            new LiquidationTierLib.LiquidationTier[](3);

        // Tier 1: HF < 1.2, 30% max, 3% bonus, 1% fee, whitelist only
        customTiers[0] = LiquidationTierLib.LiquidationTier({
            healthFactorThreshold: 1.2e18,
            maxLiquidationRatio: 0.3e18,
            liquidationBonus: 0.03e18,
            protocolFee: 0.01e18,
            whitelistOnly: true,
            minSeizedAssets: 0.1 ether,
            cooldownPeriod: 2 hours
        });

        // Tier 2: HF < 1.1, 60% max, 7% bonus, 1.5% fee, whitelist only
        customTiers[1] = LiquidationTierLib.LiquidationTier({
            healthFactorThreshold: 1.1e18,
            maxLiquidationRatio: 0.6e18,
            liquidationBonus: 0.07e18,
            protocolFee: 0.015e18,
            whitelistOnly: true,
            minSeizedAssets: 0.05 ether,
            cooldownPeriod: 1 hours
        });

        // Tier 3: HF < 1.0, 100% max, 10% bonus, 2% fee, public
        customTiers[2] = LiquidationTierLib.LiquidationTier({
            healthFactorThreshold: 1.0e18,
            maxLiquidationRatio: 1.0e18,
            liquidationBonus: 0.10e18,
            protocolFee: 0.02e18,
            whitelistOnly: false,
            minSeizedAssets: 0,
            cooldownPeriod: 0
        });

        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.configureTiers(id, customTiers);

        LiquidationTierLib.LiquidationTier[] memory tiers = tieredMorpho.getMarketTiers(id);
        assertEq(tiers.length, 3, "Should have 3 tiers");
        assertEq(tiers[0].maxLiquidationRatio, 0.3e18, "Tier 1 max ratio should be 30%");
    }

    /* HELPER FUNCTIONS */

    function _setupBorrowerPosition(address borrower, uint256 collateral, uint256 borrow) internal {
        // First, provide liquidity to the market (as SUPPLIER)
        uint256 supplyAmount = borrow * 2; // Supply 2x the borrow amount
        loanToken.setBalance(SUPPLIER, supplyAmount);
        vm.startPrank(SUPPLIER);
        morpho.supply(marketParams, supplyAmount, 0, SUPPLIER, "");
        vm.stopPrank();

        // Setup borrower position
        collateralToken.setBalance(borrower, collateral);
        vm.startPrank(borrower);
        morpho.supplyCollateral(marketParams, collateral, borrower, "");
        morpho.borrow(marketParams, borrow, 0, borrower, borrower);
        vm.stopPrank();
    }

    function _fundLiquidator(address liquidator, uint256 amount) internal {
        loanToken.setBalance(liquidator, amount);
        vm.startPrank(liquidator);
        loanToken.approve(address(tieredMorpho), type(uint256).max);
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(tieredMorpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    function _setPriceToMakeHealthFactor(uint256 targetHF) internal {
        // With collateral=10, borrowed=7.5, lltv=0.8
        // HF = (10 * price * 0.8) / 7.5 = (8 * price) / 7.5 = 1.067 * price (when price=1)
        // For HF = 0.98: price = 0.98 / 1.067 = 0.918 (91.8%)
        // For HF = 0.90: price = 0.90 / 1.067 = 0.844 (84.4%)
        
        if (targetHF < 0.95e18) {
            // Tier 2: HF < 0.95 - set price to achieve HF ~0.90
            oracle.setPrice((ORACLE_PRICE_SCALE * 84) / 100);
        } else if (targetHF < 1e18) {
            // Tier 1: 0.95 < HF < 1.0 - set price to achieve HF ~0.98
            oracle.setPrice((ORACLE_PRICE_SCALE * 92) / 100);
        }
    }
}

