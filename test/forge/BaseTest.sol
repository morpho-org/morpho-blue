// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SigUtils} from "test/forge/helpers/SigUtils.sol";
import "src/Morpho.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract BaseTest is Test {
    using MathLib for uint256;
    using MarketLib for Market;

    uint256 internal constant HIGH_COLLATERAL_AMOUNT = 1e35;
    uint256 internal constant MIN_TEST_AMOUNT = 100;
    uint256 internal constant MAX_TEST_AMOUNT = 1e28;
    uint256 internal constant MIN_TEST_SHARES = MIN_TEST_AMOUNT * SharesMathLib.VIRTUAL_SHARES;
    uint256 internal constant MAX_TEST_SHARES = MAX_TEST_AMOUNT * SharesMathLib.VIRTUAL_SHARES;
    uint256 internal constant MIN_COLLATERAL_PRICE = 1000;
    uint256 internal constant MAX_COLLATERAL_PRICE = 1e40;

    address internal SUPPLIER = _addrFromHashedString("Morpho Supplier");
    address internal BORROWER = _addrFromHashedString("Morpho Borrower");
    address internal REPAYER = _addrFromHashedString("Morpho Repayer");
    address internal ONBEHALF = _addrFromHashedString("Morpho On Behalf");
    address internal RECEIVER = _addrFromHashedString("Morpho Receiver");
    address internal LIQUIDATOR = _addrFromHashedString("Morpho Liquidator");
    address internal OWNER = _addrFromHashedString("Morpho Owner");

    uint256 internal constant LLTV = 0.8 ether;

    Morpho internal morpho;
    ERC20 internal borrowableToken;
    ERC20 internal collateralToken;
    Oracle internal oracle;
    Irm internal irm;
    Market internal market;
    Id internal id;

    function setUp() public {
        vm.label(OWNER, "Owner");
        vm.label(SUPPLIER, "Supplier");
        vm.label(BORROWER, "Borrower");
        vm.label(REPAYER, "Repayer");
        vm.label(ONBEHALF, "OnBehalf");
        vm.label(RECEIVER, "Receiver");
        vm.label(LIQUIDATOR, "Liquidator");

        // Create Morpho.
        morpho = new Morpho(OWNER);
        vm.label(address(morpho), "Morpho");

        // List a market.
        borrowableToken = new ERC20("borrowable", "B");
        vm.label(address(borrowableToken), "Borrowable asset");

        collateralToken = new ERC20("collateral", "C");
        vm.label(address(collateralToken), "Collateral asset");

        oracle = new Oracle();
        vm.label(address(oracle), "Oracle");

        oracle.setPrice(1e36);

        irm = new Irm(morpho);
        vm.label(address(irm), "IRM");

        market = Market(address(borrowableToken), address(collateralToken), address(oracle), address(irm), LLTV);
        id = market.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);
        morpho.createMarket(market);
        vm.stopPrank();

        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.startPrank(SUPPLIER);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(BORROWER);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(REPAYER);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(LIQUIDATOR);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(ONBEHALF);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.setAuthorization(BORROWER, true);
        vm.stopPrank();

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1 days);
    }

    function _addrFromHashedString(string memory str) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(str)))));
    }

    function _supply(uint256 amount) internal {
        borrowableToken.setBalance(address(this), amount);
        morpho.supply(market, amount, 0, address(this));
    }

    function _supplyCollateralForBorrower(address borrower) internal {
        collateralToken.setBalance(borrower, HIGH_COLLATERAL_AMOUNT);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(market, HIGH_COLLATERAL_AMOUNT, borrower);
        vm.stopPrank();
    }

    function _boundHealthyPosition(uint256 amountCollateral, uint256 amountBorrowed, uint256 priceCollateral)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 minCollateral = amountBorrowed.wDivUp(market.lltv).mulDivUp(ORACLE_PRICE_SCALE, priceCollateral);
        // vm.assume(minCollateral <= MAX_TEST_AMOUNT);

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

        uint256 maxCollateral = amountBorrowed.wDivDown(market.lltv).mulDivDown(ORACLE_PRICE_SCALE, priceCollateral);
        vm.assume(
            maxCollateral.mulDivDown(priceCollateral, ORACLE_PRICE_SCALE).wMulDown(market.lltv) < amountBorrowed
                && maxCollateral > 0
        );

        amountCollateral = bound(amountBorrowed, 1, maxCollateral);

        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundValidLltv(uint256 lltv) internal view returns (uint256) {
        return bound(lltv, 0, WAD - 1);
    }

    function _boundInvalidLltv(uint256 lltv) internal view returns (uint256) {
        return bound(lltv, WAD, type(uint256).max);
    }

    function _liquidationIncentive(uint256 lltv) internal pure returns (uint256) {
        return
            UtilsLib.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
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
