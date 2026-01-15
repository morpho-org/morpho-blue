// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {TieredLiquidationMorpho} from "../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../src/extensions/WhitelistRegistry.sol";
import {IMorpho} from "../src/interfaces/IMorpho.sol";

/// @title DeployTieredLiquidation
/// @notice Deployment script for Tiered Liquidation system
contract DeployTieredLiquidation is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address morphoAddress = vm.envAddress("MORPHO_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy WhitelistRegistry
        WhitelistRegistry whitelistRegistry = new WhitelistRegistry(owner);
        console.log("WhitelistRegistry deployed at:", address(whitelistRegistry));

        // 2. Deploy TieredLiquidationMorpho
        TieredLiquidationMorpho tieredMorpho = new TieredLiquidationMorpho(
            morphoAddress,
            address(whitelistRegistry)
        );
        console.log("TieredLiquidationMorpho deployed at:", address(tieredMorpho));

        // 3. Transfer ownership if needed
        if (tieredMorpho.owner() != owner) {
            tieredMorpho.transferOwnership(owner);
            console.log("Transferred TieredLiquidationMorpho ownership to:", owner);
        }

        vm.stopBroadcast();

        // Output deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("WhitelistRegistry:", address(whitelistRegistry));
        console.log("TieredLiquidationMorpho:", address(tieredMorpho));
        console.log("Owner:", owner);
        console.log("Morpho:", morphoAddress);
    }
}

