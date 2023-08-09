// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract BaseTest is Test {
    using FixedPointMathLib for uint256;
    using MarketLib for Market;

    uint256 internal constant MIN_TEST_AMOUNT = 1000;
    uint256 internal constant MAX_TEST_AMOUNT = 2 ** 64;
    uint256 internal constant MIN_COLLATERAL_PRICE = 100;
    uint256 internal constant MAX_COLLATERAL_PRICE = 2 ** 64;
    address internal constant BORROWER = address(uint160(uint256(keccak256("Morpho Blue Borrower"))));
    address internal constant LIQUIDATOR = address(uint160(uint256(keccak256("Morpho Blue Liquidator"))));
    uint256 internal constant LLTV = 0.8 ether;
    address internal constant OWNER = address(uint160(uint256(keccak256("Morpho Blue Owner"))));
    Blue internal blue;
    ERC20 internal borrowableAsset;
    ERC20 internal collateralAsset;
    Oracle internal borrowableOracle;
    Oracle internal collateralOracle;
    Irm internal irm;
    Market public market;
    Id public id;

    function setUp() virtual public {
        vm.label(OWNER, "Owner");
        vm.label(BORROWER, "Borrower");
        vm.label(LIQUIDATOR, "Liquidator");

        // Create Blue.
        blue = new Blue(OWNER);
        vm.label(address(blue), "Blue");

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        vm.label(address(borrowableAsset), "Borrowable asset");

        collateralAsset = new ERC20("collateral", "C", 18);
        vm.label(address(collateralAsset), "Collateral asset");

        borrowableOracle = new Oracle();
        vm.label(address(borrowableOracle), "Borrowable oracle");

        collateralOracle = new Oracle();
        vm.label(address(collateralOracle), "Collateral oracle");

        irm = new Irm(blue);
        vm.label(address(irm), "IRM");

        market = Market(
            address(borrowableAsset),
            address(collateralAsset),
            address(borrowableOracle),
            address(collateralOracle),
            address(irm),
            LLTV
        );
        id = market.id();

        vm.startPrank(OWNER);
        blue.enableIrm(address(irm));
        blue.enableLltv(LLTV);
        blue.createMarket(market);
        vm.stopPrank();

        // We set the price of the borrowable asset to zero so that borrowers
        // don't need to deposit any collateral.
        borrowableOracle.setPrice(0);
        collateralOracle.setPrice(1e18);

        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.startPrank(BORROWER);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(LIQUIDATOR);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
        vm.stopPrank();
    }

    function _provideLiquidity(uint256 amount) internal {
        borrowableAsset.setBalance(address(this), amount);
        blue.supply(market, amount, address(this), hex"");
    }

    function _boundHealthyPosition(uint256 amountCollateral, uint256 amountBorrowed, uint256 priceCollateral)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 minCollateral = amountBorrowed.divWadUp(market.lltv).divWadUp(priceCollateral);

        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, MAX_TEST_AMOUNT));

        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundUnhealthyPosition(uint256 amountCollateral, uint256 amountBorrowed, uint256 priceCollateral)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 maxCollateral = amountBorrowed.divWadDown(market.lltv).divWadDown(priceCollateral);
        vm.assume(maxCollateral != 0);

        amountCollateral = bound(amountBorrowed, 1, maxCollateral);

        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundValidLltv(uint256 lltv) internal view returns (uint256) {
        return bound(lltv, 0, FixedPointMathLib.WAD - 1);
    }

    function _boundInvalidLltv(uint256 lltv) internal view returns (uint256) {
        return bound(lltv, FixedPointMathLib.WAD, type(uint256).max);
    }

    function _liquidationIncentive(uint256 lltv) internal pure returns (uint256) {
        return FixedPointMathLib.WAD + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(lltv) - FixedPointMathLib.WAD);
    }

    function neq(Market memory a, Market memory b) internal pure returns (bool) {
        return (Id.unwrap(a.id()) != Id.unwrap(b.id()));
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
