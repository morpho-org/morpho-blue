// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {TieredLiquidationMorpho} from "../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../src/extensions/WhitelistRegistry.sol";
import {LiquidationTierLib} from "../src/extensions/libraries/LiquidationTierLib.sol";
import {Id, MarketParams} from "../src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../src/libraries/MarketParamsLib.sol";

/// @title ConfigureTieredLiquidation
/// @notice Script to configure tiered liquidation for a market
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

        TieredLiquidationMorpho tieredMorpho = TieredLiquidationMorpho(tieredMorphoAddress);
        WhitelistRegistry whitelistRegistry = WhitelistRegistry(whitelistRegistryAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Initialize market in whitelist registry
        address marketAdmin = vm.envAddress("MARKET_ADMIN");
        whitelistRegistry.initializeMarket(marketId, marketAdmin);
        console.log("Market initialized with admin:", marketAdmin);

        // 2. Enable tiered liquidation with default tiers
        tieredMorpho.enableTieredLiquidation(marketId);
        console.log("Tiered liquidation enabled for market:", uint256(Id.unwrap(marketId)));

        // 3. Enable whitelist mode
        whitelistRegistry.setWhitelistMode(marketId, true);
        console.log("Whitelist mode enabled");

        vm.stopBroadcast();

        console.log("\n=== Configuration Complete ===");
        console.log("Market ID:", uint256(Id.unwrap(marketId)));
        console.log("Market Admin:", marketAdmin);
        console.log("Tiered Liquidation:", tieredMorpho.isTieredLiquidationEnabled(marketId));
        console.log("Whitelist Enabled:", whitelistRegistry.isWhitelistEnabled(marketId));
    }
}

