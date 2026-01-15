// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract CreateMarketIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    function testCreateMarketWithNotEnabledIrmAndNotEnabledLltv(MarketParams memory marketParamsFuzz) public {
        vm.assume(!morpho.isIrmEnabled(marketParamsFuzz.irm) && !morpho.isLltvEnabled(marketParamsFuzz.lltv));

        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);
    }

    function testCreateMarketWithNotEnabledIrmAndEnabledLltv(MarketParams memory marketParamsFuzz) public {
        vm.assume(!morpho.isIrmEnabled(marketParamsFuzz.irm));

        vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);
    }

    function testCreateMarketWithEnabledIrmAndNotEnabledLltv(MarketParams memory marketParamsFuzz) public {
        vm.assume(!morpho.isLltvEnabled(marketParamsFuzz.lltv));

        vm.startPrank(OWNER);
        if (!morpho.isIrmEnabled(marketParamsFuzz.irm)) morpho.enableIrm(marketParamsFuzz.irm);
        vm.stopPrank();

        vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);
    }

    function testCreateMarketWithEnabledIrmAndLltv(MarketParams memory marketParamsFuzz) public {
        marketParamsFuzz.irm = address(irm);
        marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);
        Id marketParamsFuzzId = marketParamsFuzz.id();

        vm.startPrank(OWNER);
        if (!morpho.isLltvEnabled(marketParamsFuzz.lltv)) morpho.enableLltv(marketParamsFuzz.lltv);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.CreateMarket(marketParamsFuzz.id(), marketParamsFuzz);
        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);

        assertEq(morpho.lastUpdate(marketParamsFuzzId), block.timestamp, "lastUpdate != block.timestamp");
        assertEq(morpho.totalSupplyAssets(marketParamsFuzzId), 0, "totalSupplyAssets != 0");
        assertEq(morpho.totalSupplyShares(marketParamsFuzzId), 0, "totalSupplyShares != 0");
        assertEq(morpho.totalBorrowAssets(marketParamsFuzzId), 0, "totalBorrowAssets != 0");
        assertEq(morpho.totalBorrowShares(marketParamsFuzzId), 0, "totalBorrowShares != 0");
        assertEq(morpho.fee(marketParamsFuzzId), 0, "fee != 0");
    }

    function testCreateMarketAlreadyCreated(MarketParams memory marketParamsFuzz) public {
        marketParamsFuzz.irm = address(irm);
        marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);

        vm.startPrank(OWNER);
        if (!morpho.isLltvEnabled(marketParamsFuzz.lltv)) morpho.enableLltv(marketParamsFuzz.lltv);
        vm.stopPrank();

        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);

        vm.expectRevert(bytes(ErrorsLib.MARKET_ALREADY_CREATED));
        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);
    }

    function testIdToMarketParams(MarketParams memory marketParamsFuzz) public {
        marketParamsFuzz.irm = address(irm);
        marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);
        Id marketParamsFuzzId = marketParamsFuzz.id();

        vm.startPrank(OWNER);
        if (!morpho.isLltvEnabled(marketParamsFuzz.lltv)) morpho.enableLltv(marketParamsFuzz.lltv);
        vm.stopPrank();

        vm.prank(OWNER);
        morpho.createMarket(marketParamsFuzz);

        MarketParams memory params = morpho.idToMarketParams(marketParamsFuzzId);

        assertEq(marketParamsFuzz.loanToken, params.loanToken, "loanToken != loanToken");
        assertEq(marketParamsFuzz.collateralToken, params.collateralToken, "collateralToken != collateralToken");
        assertEq(marketParamsFuzz.oracle, params.oracle, "oracle != oracle");
        assertEq(marketParamsFuzz.irm, params.irm, "irm != irm");
        assertEq(marketParamsFuzz.lltv, params.lltv, "lltv != lltv");
    }
}
