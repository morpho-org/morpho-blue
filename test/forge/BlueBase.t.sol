// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Blue.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract BlueBaseTest is Test {
    using FixedPointMathLib for uint256;

    uint256 internal constant MAX_TEST_AMOUNT = 2 ** 64;
    uint256 internal constant MIN_COLLATERAL_PRICE = 100;
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

    function setUp() public {
        // Create Blue.
        blue = new Blue(OWNER);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        borrowableOracle = new Oracle();
        collateralOracle = new Oracle();

        irm = new Irm(blue);
        market = Market(
            address(borrowableAsset),
            address(collateralAsset),
            address(borrowableOracle),
            address(collateralOracle),
            address(irm),
            LLTV
        );
        id = Id.wrap(keccak256(abi.encode(market)));

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

    function supplyBalance(address user) internal view returns (uint256) {
        uint256 supplyShares = blue.supplyShares(id, user);
        if (supplyShares == 0) return 0;

        uint256 totalShares = blue.totalSupplyShares(id);
        uint256 totalSupply = blue.totalSupply(id);
        return supplyShares.divWadDown(totalShares).mulWadDown(totalSupply);
    }

    function borrowBalance(address user) internal view returns (uint256) {
        uint256 borrowerShares = blue.borrowShares(id, user);
        if (borrowerShares == 0) return 0;

        uint256 totalShares = blue.totalBorrowShares(id);
        uint256 totalBorrow = blue.totalBorrow(id);
        return borrowerShares.divWadUp(totalShares).mulWadUp(totalBorrow);
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
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1000, MAX_TEST_AMOUNT);

        uint256 minCollateral = amountBorrowed.divWadUp(market.lltv).divWadUp(priceCollateral);
        vm.assume(minCollateral != 0);

        amountCollateral = bound(amountCollateral, minCollateral, max(minCollateral, MAX_TEST_AMOUNT));

        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundUnhealthyPosition(uint256 amountCollateral, uint256 amountBorrowed, uint256 priceCollateral)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1000, MAX_TEST_AMOUNT);

        uint256 maxCollateral = amountBorrowed.divWadDown(market.lltv).divWadDown(priceCollateral);
        vm.assume(maxCollateral != 0);

        amountCollateral = bound(amountBorrowed, 1, maxCollateral);

        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundValidLltv(uint256 lltv) internal pure returns (uint256) {
        return _bound(lltv, 0, FixedPointMathLib.WAD - 1);
    }

    function _boundInvalidLltv(uint256 lltv) internal pure returns (uint256) {
        return _bound(lltv, FixedPointMathLib.WAD, type(uint256).max);
    }

    function _incentive(uint256 lltv) internal pure returns (uint256) {
        return FixedPointMathLib.WAD + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(lltv) - FixedPointMathLib.WAD);
    }

    function neq(Market memory a, Market memory b) internal pure returns (bool) {
        return (keccak256(abi.encode(a)) != keccak256(abi.encode(b)));
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
