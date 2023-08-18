// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationCreateMarketTest is BaseTest {
    using MorphoLib for Morpho;
    using MarketLib for Config;
    using MathLib for uint256;

    function testCreateMarketWithNotEnabledIrmAndNotEnabledLltv(Config memory configFuzz) public {
        vm.assume(configFuzz.irm != address(irm) && configFuzz.lltv != LLTV);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(configFuzz);
    }

    function testCreateMarketWithNotEnabledIrmAndEnabledLltv(Config memory configFuzz) public {
        vm.assume(configFuzz.irm != address(irm));
        configFuzz.lltv = _boundValidLltv(configFuzz.lltv);

        vm.startPrank(OWNER);
        if (configFuzz.lltv != LLTV) morpho.enableLltv(configFuzz.lltv);

        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(configFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndNotEnabledLltv(Config memory configFuzz) public {
        vm.assume(configFuzz.lltv != LLTV);

        vm.startPrank(OWNER);
        if (configFuzz.irm != market.irm) morpho.enableIrm(configFuzz.irm);

        vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
        morpho.createMarket(configFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndLltv(Config memory configFuzz) public {
        configFuzz.lltv = _boundValidLltv(configFuzz.lltv);
        Id configFuzzId = configFuzz.id();

        vm.startPrank(OWNER);
        if (configFuzz.irm != market.irm) morpho.enableIrm(configFuzz.irm);
        if (configFuzz.lltv != LLTV) morpho.enableLltv(configFuzz.lltv);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.CreateMarket(configFuzz.id(), configFuzz);
        morpho.createMarket(configFuzz);
        vm.stopPrank();

        assertEq(morpho.lastUpdate(configFuzzId), block.timestamp, "lastUpdate != block.timestamp");
        assertEq(morpho.totalSupply(configFuzzId), 0, "totalSupply != 0");
        assertEq(morpho.totalSupplyShares(configFuzzId), 0, "totalSupplyShares != 0");
        assertEq(morpho.totalBorrow(configFuzzId), 0, "totalBorrow != 0");
        assertEq(morpho.totalBorrowShares(configFuzzId), 0, "totalBorrowShares != 0");
        assertEq(morpho.fee(configFuzzId), 0, "fee != 0");
    }

    function testCreateMarketAlreadyCreated(Config memory configFuzz) public {
        configFuzz.lltv = _boundValidLltv(configFuzz.lltv);

        vm.startPrank(OWNER);
        if (configFuzz.irm != market.irm) morpho.enableIrm(configFuzz.irm);
        if (configFuzz.lltv != LLTV) morpho.enableLltv(configFuzz.lltv);
        morpho.createMarket(configFuzz);

        vm.expectRevert(bytes(ErrorsLib.MARKET_ALREADY_CREATED));
        morpho.createMarket(configFuzz);
        vm.stopPrank();
    }
}
