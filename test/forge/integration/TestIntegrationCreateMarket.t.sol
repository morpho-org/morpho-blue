// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationCreateMarketTest is BaseTest {
    using MorphoLib for Morpho;
    using MarketLib for MarketParams;
    using MathLib for uint256;

    function testCreateMarketWithNotEnabledIrmAndNotEnabledLltv(MarketParams memory marketParamsFuzz) public {
        vm.assume(marketParamsFuzz.irm != address(irm) && marketParamsFuzz.lltv != LLTV);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(marketParamsFuzz);
    }

    function testCreateMarketWithNotEnabledIrmAndEnabledLltv(MarketParams memory marketParamsFuzz) public {
        vm.assume(marketParamsFuzz.irm != address(irm));
        marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);

        vm.startPrank(OWNER);
        if (marketParamsFuzz.lltv != LLTV) morpho.enableLltv(marketParamsFuzz.lltv);

        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        morpho.createMarket(marketParamsFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndNotEnabledLltv(MarketParams memory marketParamsFuzz) public {
        vm.assume(marketParamsFuzz.lltv != LLTV);

        vm.startPrank(OWNER);
        if (marketParamsFuzz.irm != market.irm) morpho.enableIrm(marketParamsFuzz.irm);

        vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
        morpho.createMarket(marketParamsFuzz);
        vm.stopPrank();
    }

    function testCreateMarketWithEnabledIrmAndLltv(MarketParams memory marketParamsFuzz) public {
        marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);
        Id marketParamsFuzzId = marketParamsFuzz.id();

        vm.startPrank(OWNER);
        if (marketParamsFuzz.irm != market.irm) morpho.enableIrm(marketParamsFuzz.irm);
        if (marketParamsFuzz.lltv != LLTV) morpho.enableLltv(marketParamsFuzz.lltv);

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.CreateMarket(marketParamsFuzz.id(), marketParamsFuzz);
        morpho.createMarket(marketParamsFuzz);
        vm.stopPrank();

        assertEq(morpho.lastUpdate(marketParamsFuzzId), block.timestamp, "lastUpdate != block.timestamp");
        assertEq(morpho.totalSupplyAssets(marketParamsFuzzId), 0, "totalSupplyAssets != 0");
        assertEq(morpho.totalSupplyShares(marketParamsFuzzId), 0, "totalSupplyShares != 0");
        assertEq(morpho.totalBorrowAssets(marketParamsFuzzId), 0, "totalBorrowAssets != 0");
        assertEq(morpho.totalBorrowShares(marketParamsFuzzId), 0, "totalBorrowShares != 0");
        assertEq(morpho.fee(marketParamsFuzzId), 0, "fee != 0");
    }

    function testCreateMarketAlreadyCreated(MarketParams memory marketParamsFuzz) public {
        marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);

        vm.startPrank(OWNER);
        if (marketParamsFuzz.irm != market.irm) morpho.enableIrm(marketParamsFuzz.irm);
        if (marketParamsFuzz.lltv != LLTV) morpho.enableLltv(marketParamsFuzz.lltv);
        morpho.createMarket(marketParamsFuzz);

        vm.expectRevert(bytes(ErrorsLib.MARKET_ALREADY_CREATED));
        morpho.createMarket(marketParamsFuzz);
        vm.stopPrank();
    }
}
