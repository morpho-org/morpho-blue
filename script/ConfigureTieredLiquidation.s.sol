// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/Script.sol";
import {TieredLiquidationMorpho} from "../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../src/extensions/WhitelistRegistry.sol";
import {Id, MarketParams} from "../src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../src/libraries/MarketParamsLib.sol";

/// @title ConfigureTieredLiquidation
/// @notice Script to configure tiered liquidation for a market with hybrid mode support
/// @dev Supports both public one-step and whitelist two-step liquidation modes
contract ConfigureTieredLiquidation is Script {
    using MarketParamsLib for MarketParams;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tieredMorphoAddress = vm.envAddress("TIERED_MORPHO_ADDRESS");
        address whitelistRegistryAddress = vm.envAddress("WHITELIST_REGISTRY_ADDRESS");

        // Market parameters
        address loanToken = vm.envAddress("LOAN_TOKEN");
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        address oracle = vm.envAddress("ORACLE");
        address irm = vm.envAddress("IRM");
        uint256 lltv = vm.envUint("LLTV");

        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        Id marketId = marketParams.id();

        TieredLiquidationMorpho tieredMorpho = TieredLiquidationMorpho(payable(tieredMorphoAddress));
        WhitelistRegistry whitelistRegistry = WhitelistRegistry(whitelistRegistryAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Initialize market in whitelist registry
        address marketAdmin = vm.envAddress("MARKET_ADMIN");
        whitelistRegistry.initializeMarket(marketId, marketAdmin);
        console.log("Market initialized with admin:", marketAdmin);

        // 2. Configure market with hybrid mode support
        // Parameters:
        // - enabled: true
        // - liquidationBonus: 10% (0.1e18)
        // - maxLiquidationRatio: 100% (1e18)
        // - cooldownPeriod: 1 hour
        // - minSeizedAssets: 0.01 ETH equivalent
        // - publicLiquidationEnabled: true (allow public one-step liquidation)
        // - twoStepLiquidationEnabled: true (allow whitelist two-step liquidation)
        // - lockDuration: 1 hour (time window for two-step execution)
        // - requestDeposit: 0.1 ETH (deposit required for two-step request)
        // - protocolFee: 50% (0.5e18) of liquidation bonus goes to protocol
        tieredMorpho.configureMarket(
            marketId,
            true,           // enabled
            0.1e18,         // liquidationBonus (10%)
            1e18,           // maxLiquidationRatio (100%)
            1 hours,        // cooldownPeriod
            0.01 ether,     // minSeizedAssets
            true,           // publicLiquidationEnabled
            true,           // twoStepLiquidationEnabled
            1 hours,        // lockDuration
            0.1 ether,      // requestDeposit
            0.5e18          // protocolFee (50%)
        );
        console.log("Hybrid liquidation configured for market:", uint256(Id.unwrap(marketId)));

        // 3. Enable whitelist mode for VIP liquidators
        whitelistRegistry.setWhitelistMode(marketId, true);
        console.log("Whitelist mode enabled");

        vm.stopBroadcast();

        console.log("\n=== Configuration Complete ===");
        console.log("Market ID:", uint256(Id.unwrap(marketId)));
        console.log("Market Admin:", marketAdmin);
        
        // Check configuration (struct order: enabled, publicLiquidationEnabled, twoStepLiquidationEnabled, liquidationBonus, ...)
        (
            bool enabled,
            bool publicLiquidationEnabled,
            bool twoStepLiquidationEnabled,
            uint256 liquidationBonus,
            uint256 maxLiquidationRatio,
            uint256 cooldownPeriod,
            uint256 minSeizedAssets,
            uint256 protocolFee,
            uint256 lockDuration,
            uint256 requestDeposit
        ) = tieredMorpho.marketConfigs(marketId);
        
        console.log("\n=== Market Configuration ===");
        console.log("Enabled:", enabled);
        console.log("Public Liquidation Enabled:", publicLiquidationEnabled);
        console.log("Two-Step Liquidation Enabled:", twoStepLiquidationEnabled);
        console.log("Liquidation Bonus:", liquidationBonus);
        console.log("Max Liquidation Ratio:", maxLiquidationRatio);
        console.log("Cooldown Period:", cooldownPeriod);
        console.log("Min Seized Assets:", minSeizedAssets);
        console.log("Protocol Fee:", protocolFee);
        console.log("Lock Duration:", lockDuration);
        console.log("Request Deposit:", requestDeposit);
        console.log("Whitelist Enabled:", whitelistRegistry.isWhitelistEnabled(marketId));
    }

    /// @notice Configure market for public-only mode (no whitelist requirements)
    function configurePublicOnlyMode(
        address tieredMorphoAddress,
        Id marketId
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        TieredLiquidationMorpho tieredMorpho = TieredLiquidationMorpho(payable(tieredMorphoAddress));

        vm.startBroadcast(deployerPrivateKey);

        tieredMorpho.configureMarket(
            marketId,
            true,           // enabled
            0.1e18,         // liquidationBonus (10%)
            1e18,           // maxLiquidationRatio (100%)
            0,              // cooldownPeriod (no cooldown)
            0.01 ether,     // minSeizedAssets
            true,           // publicLiquidationEnabled (anyone can liquidate)
            false,          // twoStepLiquidationEnabled (no two-step)
            0,              // lockDuration (not needed)
            0,              // requestDeposit (not needed)
            0.5e18          // protocolFee (50%)
        );

        vm.stopBroadcast();
        console.log("Public-only mode configured for market:", uint256(Id.unwrap(marketId)));
    }

    /// @notice Configure market for whitelist two-step only mode
    function configureWhitelistTwoStepOnlyMode(
        address tieredMorphoAddress,
        Id marketId
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        TieredLiquidationMorpho tieredMorpho = TieredLiquidationMorpho(payable(tieredMorphoAddress));

        vm.startBroadcast(deployerPrivateKey);

        tieredMorpho.configureMarket(
            marketId,
            true,           // enabled
            0.1e18,         // liquidationBonus (10%)
            0.5e18,         // maxLiquidationRatio (50% - more conservative for VIP)
            1 hours,        // cooldownPeriod
            0.01 ether,     // minSeizedAssets
            false,          // publicLiquidationEnabled (public cannot liquidate)
            true,           // twoStepLiquidationEnabled (whitelist only two-step)
            2 hours,        // lockDuration (2 hour window for VIP to prepare funds)
            0.5 ether,      // requestDeposit (higher deposit for commitment)
            0.3e18          // protocolFee (30% - lower fee for VIP)
        );

        vm.stopBroadcast();
        console.log("Whitelist two-step only mode configured for market:", uint256(Id.unwrap(marketId)));
    }
}
