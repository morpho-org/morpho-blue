// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/Script.sol";
import {WhitelistRegistry} from "../src/extensions/WhitelistRegistry.sol";
import {Id, MarketParams} from "../src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../src/libraries/MarketParamsLib.sol";

/// @title AddLiquidators
/// @notice Script to add liquidators to market whitelist
contract AddLiquidators is Script {
    using MarketParamsLib for MarketParams;

    function run() external {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address whitelistRegistryAddress = vm.envAddress("WHITELIST_REGISTRY_ADDRESS");
        
        // Market parameters
        address loanToken = vm.envAddress("LOAN_TOKEN");
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        address oracle = vm.envAddress("ORACLE");
        address irm = vm.envAddress("IRM");
        uint256 lltv = vm.envUint("LLTV");

        MarketParams memory marketParams = MarketParams({
            loanToken: loanToken,
            collateralToken: collateralToken,
            oracle: oracle,
            irm: irm,
            lltv: lltv
        });

        Id marketId = marketParams.id();
        
        WhitelistRegistry registry = WhitelistRegistry(whitelistRegistryAddress);

        vm.startBroadcast(adminPrivateKey);

        // Add liquidators (configure these addresses as needed)
        address[] memory liquidators = new address[](3);
        liquidators[0] = vm.envAddress("LIQUIDATOR_1");
        liquidators[1] = vm.envAddress("LIQUIDATOR_2");
        liquidators[2] = vm.envAddress("LIQUIDATOR_3");

        registry.batchAddLiquidators(marketId, liquidators);

        console.log("Added", liquidators.length, "liquidators to market");
        for (uint256 i = 0; i < liquidators.length; i++) {
            console.log("Liquidator", i + 1, ":", liquidators[i]);
        }

        vm.stopBroadcast();
    }
}

