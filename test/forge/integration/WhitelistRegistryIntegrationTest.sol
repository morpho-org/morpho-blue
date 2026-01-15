// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import {WhitelistRegistry} from "../../../src/extensions/WhitelistRegistry.sol";

contract WhitelistRegistryIntegrationTest is BaseTest {
    WhitelistRegistry public registry;

    address public admin1 = makeAddr("admin1");
    address public admin2 = makeAddr("admin2");
    address public liquidator1 = makeAddr("liquidator1");
    address public liquidator2 = makeAddr("liquidator2");
    address public liquidator3 = makeAddr("liquidator3");

    function setUp() public override {
        super.setUp();
        registry = new WhitelistRegistry(OWNER);
    }

    function testInitializeMarket() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        assertEq(registry.marketAdmin(id), admin1, "Admin should be set");
    }

    function testInitializeMarketTwiceShouldFail() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.expectRevert(WhitelistRegistry.AlreadySet.selector);
        registry.initializeMarket(id, admin2);
    }

    function testAddLiquidator() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.prank(admin1);
        registry.addLiquidator(id, liquidator1);

        assertTrue(registry.isAuthorizedLiquidator(id, liquidator1), "Liquidator should be authorized");
        assertEq(registry.getLiquidatorCount(id), 1, "Should have 1 liquidator");
    }

    function testAddLiquidatorUnauthorized() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.prank(liquidator1);
        vm.expectRevert(WhitelistRegistry.Unauthorized.selector);
        registry.addLiquidator(id, liquidator2);
    }

    function testRemoveLiquidator() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.startPrank(admin1);
        registry.addLiquidator(id, liquidator1);
        registry.addLiquidator(id, liquidator2);
        registry.removeLiquidator(id, liquidator1);
        vm.stopPrank();

        assertFalse(registry.isAuthorizedLiquidator(id, liquidator1), "Liquidator should be removed");
        assertTrue(registry.isAuthorizedLiquidator(id, liquidator2), "Liquidator2 should still exist");
        assertEq(registry.getLiquidatorCount(id), 1, "Should have 1 liquidator");
    }

    function testCannotRemoveLastLiquidatorWhenWhitelistEnabled() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.startPrank(admin1);
        registry.addLiquidator(id, liquidator1);
        registry.setWhitelistMode(id, true);

        vm.expectRevert(WhitelistRegistry.MinLiquidatorsRequired.selector);
        registry.removeLiquidator(id, liquidator1);
        vm.stopPrank();
    }

    function testBatchAddLiquidators() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        address[] memory liquidators = new address[](3);
        liquidators[0] = liquidator1;
        liquidators[1] = liquidator2;
        liquidators[2] = liquidator3;

        vm.prank(admin1);
        registry.batchAddLiquidators(id, liquidators);

        assertEq(registry.getLiquidatorCount(id), 3, "Should have 3 liquidators");
        assertTrue(registry.isAuthorizedLiquidator(id, liquidator1), "Liquidator1 should be authorized");
        assertTrue(registry.isAuthorizedLiquidator(id, liquidator2), "Liquidator2 should be authorized");
        assertTrue(registry.isAuthorizedLiquidator(id, liquidator3), "Liquidator3 should be authorized");
    }

    function testWhitelistMode() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.startPrank(admin1);
        registry.addLiquidator(id, liquidator1);

        assertFalse(registry.isWhitelistEnabled(id), "Whitelist should be disabled by default");
        assertTrue(registry.canLiquidate(id, liquidator2), "Anyone can liquidate when disabled");

        registry.setWhitelistMode(id, true);
        assertTrue(registry.isWhitelistEnabled(id), "Whitelist should be enabled");
        assertTrue(registry.canLiquidate(id, liquidator1), "Whitelisted liquidator can liquidate");
        assertFalse(registry.canLiquidate(id, liquidator2), "Non-whitelisted cannot liquidate");
        vm.stopPrank();
    }

    function testAdminCanAlwaysLiquidate() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.prank(admin1);
        registry.setWhitelistMode(id, true);

        assertTrue(registry.canLiquidate(id, admin1), "Admin can always liquidate");
        assertTrue(registry.canLiquidate(id, OWNER), "Owner can always liquidate");
    }

    function testTransferMarketAdmin() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        // Step 1: Initiate transfer
        vm.prank(admin1);
        registry.initiateMarketAdminTransfer(id, admin2);

        // Should not be transferred yet
        assertEq(registry.marketAdmin(id), admin1, "Admin should not change immediately");

        // Step 2: Wait for timelock
        skip(2 days + 1);

        // Complete transfer
        registry.completeMarketAdminTransfer(id);

        assertEq(registry.marketAdmin(id), admin2, "Admin should be transferred");

        // Old admin should no longer have access
        vm.prank(admin1);
        vm.expectRevert(WhitelistRegistry.Unauthorized.selector);
        registry.addLiquidator(id, liquidator1);

        // New admin should have access
        vm.prank(admin2);
        registry.addLiquidator(id, liquidator1);
        assertTrue(registry.isAuthorizedLiquidator(id, liquidator1), "New admin can add liquidators");
    }

    function testDepositAndWithdrawCollateral() public {
        uint256 depositAmount = 10 ether;

        vm.deal(liquidator1, depositAmount);
        vm.prank(liquidator1);
        registry.depositCollateral{value: depositAmount}();

        assertEq(registry.liquidatorDeposit(liquidator1), depositAmount, "Deposit should be recorded");

        uint256 withdrawAmount = 5 ether;
        uint256 balanceBefore = liquidator1.balance;

        vm.prank(liquidator1);
        registry.withdrawCollateral(withdrawAmount);

        assertEq(registry.liquidatorDeposit(liquidator1), depositAmount - withdrawAmount, "Deposit should be reduced");
        assertEq(liquidator1.balance, balanceBefore + withdrawAmount, "Balance should increase");
    }

    function testRecordLiquidation() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        registry.recordLiquidation(id, liquidator1);
        registry.recordLiquidation(id, liquidator1);
        registry.recordLiquidation(id, liquidator2);

        (, , uint256 liquidations1,) = registry.getLiquidatorInfo(id, liquidator1);
        (, , uint256 liquidations2,) = registry.getLiquidatorInfo(id, liquidator2);

        assertEq(liquidations1, 2, "Liquidator1 should have 2 liquidations");
        assertEq(liquidations2, 1, "Liquidator2 should have 1 liquidation");
    }

    function testGetLiquidators() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        vm.startPrank(admin1);
        registry.addLiquidator(id, liquidator1);
        registry.addLiquidator(id, liquidator2);
        vm.stopPrank();

        address[] memory liquidators = registry.getLiquidators(id);
        assertEq(liquidators.length, 2, "Should return 2 liquidators");
        assertTrue(
            (liquidators[0] == liquidator1 && liquidators[1] == liquidator2)
                || (liquidators[0] == liquidator2 && liquidators[1] == liquidator1),
            "Should contain both liquidators"
        );
    }

    function testMaxLiquidators() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        // Set max to 2
        vm.prank(OWNER);
        registry.setMaxLiquidators(2);

        vm.startPrank(admin1);
        registry.addLiquidator(id, liquidator1);
        registry.addLiquidator(id, liquidator2);

        vm.expectRevert(WhitelistRegistry.MaxLiquidatorsExceeded.selector);
        registry.addLiquidator(id, liquidator3);
        vm.stopPrank();
    }

    function testOwnerCanManageAllMarkets() public {
        vm.prank(OWNER);
        registry.initializeMarket(id, admin1);

        // Owner can add liquidators even though they're not the market admin
        vm.prank(OWNER);
        registry.addLiquidator(id, liquidator1);

        assertTrue(registry.isAuthorizedLiquidator(id, liquidator1), "Owner should be able to add liquidators");
    }
}

