// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IrmMock} from "./IrmMock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import "./MorphoMock.sol";

import {MorphoLib} from "src/libraries/periphery/MorphoLib.sol";

contract BaseTest is Test {
    using MorphoLib for Morpho;
    using MarketParamsLib for MarketParams;

    address internal OWNER = _addrFromHashedString("Morpho Owner");

    function _addrFromHashedString(string memory str) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(str)))));
    }

    uint256 internal constant VIRTUAL_SHARES = 1e6;

    uint256 internal constant LLTV = 0.8 ether; // TODO: test with random LLTVs

    Morpho internal morpho;
    ERC20 internal borrowableToken;
    ERC20 internal collateralToken;
    Oracle internal oracle;
    IrmMock internal irm;
    MarketParams internal marketParams; // TODO: test with multiple markets
    Id internal id;

    function setUp() public {
        vm.label(OWNER, "Owner");

        // Create Morpho.
        morpho = Morpho(new MorphoMock(OWNER));
        vm.label(address(morpho), "Morpho");

        // List a market.
        borrowableToken = new ERC20();
        vm.label(address(borrowableToken), "Borrowable asset");

        collateralToken = new ERC20();
        vm.label(address(collateralToken), "Collateral asset");

        oracle = new Oracle();
        vm.label(address(oracle), "Oracle");

        oracle.setPrice(1e36); // TODO: test with random prices

        irm = new IrmMock();
        vm.label(address(irm), "IRM");

        irm.setRate(uint256(5e16) / 365 days); // 5% APR // TODO: test with random rate

        marketParams =
            MarketParams(address(borrowableToken), address(collateralToken), address(oracle), address(irm), LLTV);
        id = marketParams.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);
        morpho.createMarket(marketParams);
        vm.stopPrank();
    }
}
