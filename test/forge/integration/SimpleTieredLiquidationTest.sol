// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import {TieredLiquidationMorpho} from "../../../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../../../src/extensions/WhitelistRegistry.sol";
import {LiquidationTierLib} from "../../../src/extensions/libraries/LiquidationTierLib.sol";

contract SimpleTieredLiquidationTest is BaseTest {
    TieredLiquidationMorpho public tieredMorpho;
    WhitelistRegistry public whitelistRegistry;

    address public marketAdmin = makeAddr("marketAdmin");
    address public liquidator1 = makeAddr("liquidator1");

    function setUp() public override {
        super.setUp();

        // Deploy whitelist registry
        whitelistRegistry = new WhitelistRegistry(OWNER);

        // Deploy tiered liquidation morpho
        tieredMorpho = new TieredLiquidationMorpho(address(morpho), address(whitelistRegistry));

        // Setup market admin
        vm.prank(OWNER);
        whitelistRegistry.initializeMarket(id, marketAdmin);

        // Add liquidator to whitelist
        vm.prank(marketAdmin);
        whitelistRegistry.addLiquidator(id, liquidator1);

        // Enable tiered liquidation
        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.enableTieredLiquidation(id);
    }

    function testContractsDeployed() public {
        assertTrue(address(tieredMorpho) != address(0));
        assertTrue(address(whitelistRegistry) != address(0));
    }

    function testTieredLiquidationEnabled() public {
        assertTrue(tieredMorpho.isTieredLiquidationEnabled(id));

        LiquidationTierLib.LiquidationTier[] memory tiers = tieredMorpho.getMarketTiers(id);
        assertEq(tiers.length, 2, "Should have 2 tiers");
        // Note: Due to Morpho Blue constraint (HF < 1.0), tiers are adjusted:
        // Tier 1: Conservative (0.95 < HF < 1.0), Tier 2: Aggressive (HF < 0.95)
        assertEq(tiers[0].healthFactorThreshold, 1.0e18, "Tier 1 threshold should be 1.0");
        assertEq(tiers[1].healthFactorThreshold, 0.95e18, "Tier 2 threshold should be 0.95");
    }

    function testWhitelistConfiguration() public {
        assertTrue(whitelistRegistry.isAuthorizedLiquidator(id, liquidator1), "Liquidator should be authorized");
        assertEq(whitelistRegistry.marketAdmin(id), marketAdmin, "Market admin should be set");
    }

    function testCustomTierConfiguration() public {
        // Create custom tiers
        LiquidationTierLib.LiquidationTier[] memory customTiers =
            new LiquidationTierLib.LiquidationTier[](2);

        // Tier 1: HF < 1.2, 30% max, 3% bonus, 1% protocol fee, whitelist only
        customTiers[0] = LiquidationTierLib.LiquidationTier({
            healthFactorThreshold: 1.2e18,
            maxLiquidationRatio: 0.3e18,
            liquidationBonus: 0.03e18,
            protocolFee: 0.01e18,
            whitelistOnly: true,
            minSeizedAssets: 0.1 ether,
            cooldownPeriod: 2 hours
        });

        // Tier 2: HF < 1.0, 100% max, 10% bonus, 2% protocol fee, public
        customTiers[1] = LiquidationTierLib.LiquidationTier({
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
        assertEq(tiers.length, 2, "Should have 2 tiers");
        assertEq(tiers[0].maxLiquidationRatio, 0.3e18, "Tier 1 max ratio should be 30%");
    }

    function testDisableTieredLiquidation() public {
        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.disableTieredLiquidation(id);

        assertFalse(tieredMorpho.isTieredLiquidationEnabled(id), "Should be disabled");
    }
}

