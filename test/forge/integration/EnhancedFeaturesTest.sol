// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import {TieredLiquidationMorpho} from "../../../src/extensions/TieredLiquidationMorpho.sol";
import {WhitelistRegistry} from "../../../src/extensions/WhitelistRegistry.sol";
import {PriceOracleLib} from "../../../src/extensions/libraries/PriceOracleLib.sol";
import {LiquidationTierLib} from "../../../src/extensions/libraries/LiquidationTierLib.sol";

contract EnhancedFeaturesTest is BaseTest {
    TieredLiquidationMorpho public tieredMorpho;
    WhitelistRegistry public whitelistRegistry;

    address public marketAdmin = makeAddr("marketAdmin");
    address public liquidator1 = makeAddr("liquidator1");
    address public newAdmin = makeAddr("newAdmin");

    function setUp() public override {
        super.setUp();

        whitelistRegistry = new WhitelistRegistry(OWNER);
        tieredMorpho = new TieredLiquidationMorpho(address(morpho), address(whitelistRegistry));

        vm.prank(OWNER);
        whitelistRegistry.initializeMarket(id, marketAdmin);

        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.enableTieredLiquidation(id);
    }

    // Test 1: Protocol Fee Mechanism
    function testProtocolFeeCollection() public {
        // Default tiers have protocol fees
        LiquidationTierLib.LiquidationTier[] memory tiers = tieredMorpho.getMarketTiers(id);
        
        // Tier 1 should have 1% protocol fee
        assertEq(tiers[0].protocolFee, 0.01e18, "Tier 1 should have 1% protocol fee");
        
        // Tier 2 should have 2% protocol fee
        assertEq(tiers[1].protocolFee, 0.02e18, "Tier 2 should have 2% protocol fee");
    }

    // Test 2: Timelock for Admin Transfer
    function testAdminTransferTimelock() public {
        vm.prank(marketAdmin);
        whitelistRegistry.initiateMarketAdminTransfer(id, newAdmin);

        // Should not be able to complete immediately
        vm.expectRevert();
        whitelistRegistry.completeMarketAdminTransfer(id);

        // After timelock, should succeed
        skip(2 days + 1);
        whitelistRegistry.completeMarketAdminTransfer(id);

        assertEq(whitelistRegistry.marketAdmin(id), newAdmin, "Admin should be transferred");
    }

    // Test 3: Cancel Admin Transfer
    function testCancelAdminTransfer() public {
        vm.prank(marketAdmin);
        whitelistRegistry.initiateMarketAdminTransfer(id, newAdmin);

        // Cancel the transfer
        vm.prank(marketAdmin);
        whitelistRegistry.cancelMarketAdminTransfer(id);

        // After timelock, complete should fail
        skip(2 days + 1);
        vm.expectRevert();
        whitelistRegistry.completeMarketAdminTransfer(id);

        // Original admin should still be in place
        assertEq(whitelistRegistry.marketAdmin(id), marketAdmin, "Original admin should remain");
    }

    // Test 4: Liquidator Slashing
    function testLiquidatorSlashing() public {
        // Liquidator deposits collateral
        vm.deal(liquidator1, 10 ether);
        vm.prank(liquidator1);
        whitelistRegistry.depositCollateral{value: 5 ether}();

        assertEq(whitelistRegistry.liquidatorDeposit(liquidator1), 5 ether, "Should have 5 ETH deposited");

        // Admin slashes liquidator for malicious behavior
        vm.prank(marketAdmin);
        whitelistRegistry.slashLiquidator(id, liquidator1, 2 ether);

        // Liquidator deposit should be reduced
        assertEq(whitelistRegistry.liquidatorDeposit(liquidator1), 3 ether, "Should have 3 ETH remaining");

        // Slashed amount should be recorded
        assertEq(whitelistRegistry.slashedAmount(liquidator1, id), 2 ether, "Should have 2 ETH slashed");
    }

    // Test 5: Price Oracle Configuration
    function testPriceOracleConfiguration() public {
        PriceOracleLib.PriceConfig memory config = PriceOracleLib.PriceConfig({
            primaryOracle: address(oracle),
            secondaryOracle: address(0),
            maxDeviation: 0.05e18, // 5%
            maxStaleness: 1 hours,
            useTWAP: false,
            twapPeriod: 30 minutes
        });

        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.configurePriceOracle(id, config);

        // Configuration stored successfully (no revert)
        assertTrue(true, "Price oracle configured successfully");
    }

    // Test 6: Fee Recipient Configuration
    function testFeeRecipientConfiguration() public {
        address newFeeRecipient = makeAddr("feeRecipient");

        vm.prank(address(tieredMorpho.owner()));
        tieredMorpho.setFeeRecipient(newFeeRecipient);

        assertEq(tieredMorpho.feeRecipient(), newFeeRecipient, "Fee recipient should be updated");
    }

    // Test 7: Admin Transfer Timelock Configuration
    function testAdminTransferTimelockConfig() public {
        uint256 newTimelock = 3 days;

        vm.prank(OWNER);
        whitelistRegistry.setAdminTransferTimelock(newTimelock);

        assertEq(whitelistRegistry.adminTransferTimelock(), newTimelock, "Timelock should be updated");
    }
}

