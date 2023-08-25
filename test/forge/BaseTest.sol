// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/interfaces/IMorphoCallbacks.sol";
import {IrmMock} from "src/mocks/IrmMock.sol";
import {ERC20Mock} from "src/mocks/ERC20Mock.sol";
import {OracleMock} from "src/mocks/OracleMock.sol";

import "src/Morpho.sol";
import {Math} from "./helpers/Math.sol";
import {SigUtils} from "./helpers/SigUtils.sol";
import {MorphoLib} from "src/libraries/periphery/MorphoLib.sol";
import {MorphoBalancesLib} from "src/libraries/periphery/MorphoBalancesLib.sol";

contract BaseTest is Test {
    using Math for uint256;
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLOCK_TIME = 12;
    uint256 internal constant HIGH_COLLATERAL_AMOUNT = 1e35;
    uint256 internal constant MIN_TEST_AMOUNT = 100;
    uint256 internal constant MAX_TEST_AMOUNT = 1e28;
    uint256 internal constant MIN_TEST_SHARES = MIN_TEST_AMOUNT * SharesMathLib.VIRTUAL_SHARES;
    uint256 internal constant MAX_TEST_SHARES = MAX_TEST_AMOUNT * SharesMathLib.VIRTUAL_SHARES;
    uint256 internal constant MIN_COLLATERAL_PRICE = 1e10;
    uint256 internal constant MAX_COLLATERAL_PRICE = 1e40;
    uint256 internal constant MAX_COLLATERAL_ASSETS = type(uint128).max;

    address internal SUPPLIER;
    address internal BORROWER;
    address internal REPAYER;
    address internal ONBEHALF;
    address internal RECEIVER;
    address internal LIQUIDATOR;
    address internal OWNER;

    uint256 internal constant LLTV = 0.8 ether;

    IMorpho internal morpho;
    ERC20Mock internal borrowableToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;

    MarketParams internal marketParams;
    Id internal id;

    function setUp() public virtual {
        SUPPLIER = _addrFromHashedString("Supplier");
        BORROWER = _addrFromHashedString("Borrower");
        REPAYER = _addrFromHashedString("Repayer");
        ONBEHALF = _addrFromHashedString("OnBehalf");
        RECEIVER = _addrFromHashedString("Receiver");
        LIQUIDATOR = _addrFromHashedString("Liquidator");
        OWNER = _addrFromHashedString("Owner");

        morpho = new Morpho(OWNER);

        borrowableToken = new ERC20Mock("borrowable", "B");
        vm.label(address(borrowableToken), "Borrowable");

        collateralToken = new ERC20Mock("collateral", "C");
        vm.label(address(collateralToken), "Collateral");

        oracle = new OracleMock();

        oracle.setPrice(1e36);

        irm = new IrmMock();

        marketParams =
            MarketParams(address(borrowableToken), address(collateralToken), address(oracle), address(irm), LLTV);
        id = marketParams.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);
        morpho.createMarket(marketParams);
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

    function _addrFromHashedString(string memory name) internal returns (address addr) {
        addr = address(uint160(uint256(keccak256(bytes(name)))));
        vm.label(addr, name);
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_TIME); // Block speed should depend on test network.
    }

    /// @dev Bounds the fuzzing input to a realistic number of blocks.
    function _boundBlocks(uint256 blocks) internal view returns (uint256) {
        return bound(blocks, 1, type(uint24).max);
    }

    /// @dev Bounds the fuzzing input to a non-zero address.
    /// @dev This function should be used in place of `vm.assume` in invariant test handler functions:
    /// https://github.com/foundry-rs/foundry/issues/4190.
    function _boundAddressNotZero(address input) internal view virtual returns (address) {
        return address(uint160(bound(uint256(uint160(input)), 1, type(uint160).max)));
    }

    function _supply(uint256 amount) internal {
        borrowableToken.setBalance(address(this), amount);
        morpho.supply(marketParams, amount, 0, address(this), hex"");
    }

    function _supplyCollateralForBorrower(address borrower) internal {
        collateralToken.setBalance(borrower, HIGH_COLLATERAL_AMOUNT);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams, HIGH_COLLATERAL_AMOUNT, borrower, hex"");
        vm.stopPrank();
    }

    function _boundHealthyPosition(uint256 amountCollateral, uint256 amountBorrowed, uint256 priceCollateral)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 minCollateral = amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, priceCollateral);

        if (minCollateral <= MAX_COLLATERAL_ASSETS) {
            amountCollateral = bound(amountCollateral, minCollateral, MAX_COLLATERAL_ASSETS);
        } else {
            amountCollateral = MAX_COLLATERAL_ASSETS;
            amountBorrowed = Math.min(
                amountBorrowed.wMulDown(marketParams.lltv).mulDivDown(priceCollateral, ORACLE_PRICE_SCALE),
                MAX_TEST_AMOUNT
            );
        }

        vm.assume(amountBorrowed > 0);
        vm.assume(amountCollateral < type(uint256).max / priceCollateral);
        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundUnhealthyPosition(uint256 amountCollateral, uint256 amountBorrowed, uint256 priceCollateral)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        priceCollateral = bound(priceCollateral, MIN_COLLATERAL_PRICE, MAX_COLLATERAL_PRICE);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 maxCollateral =
            amountBorrowed.wDivDown(marketParams.lltv).mulDivDown(ORACLE_PRICE_SCALE, priceCollateral);
        amountCollateral = bound(amountBorrowed, 0, Math.min(maxCollateral, MAX_COLLATERAL_ASSETS));

        vm.assume(amountCollateral > 0);
        return (amountCollateral, amountBorrowed, priceCollateral);
    }

    function _boundValidLltv(uint256 lltv) internal view returns (uint256) {
        return bound(lltv, 0, WAD - 1);
    }

    function _boundInvalidLltv(uint256 lltv) internal view returns (uint256) {
        return bound(lltv, WAD, type(uint256).max);
    }

    function _boundSupplyCollateralAssets(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 collateral = morpho.collateral(_id, onBehalf);

        return bound(assets, 0, MAX_TEST_AMOUNT.zeroFloorSub(collateral));
    }

    function _boundWithdrawCollateralAssets(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 collateral = morpho.collateral(_id, onBehalf);

        return bound(assets, 0, MAX_TEST_AMOUNT.min(collateral));
    }

    function _boundSupplyAssets(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        uint256 supplyBalance = morpho.expectedSupplyBalance(_marketParams, onBehalf);

        return bound(assets, 0, MAX_TEST_AMOUNT.zeroFloorSub(supplyBalance));
    }

    function _boundSupplyShares(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 supplyShares = morpho.supplyShares(_id, onBehalf);

        return bound(
            assets,
            0,
            MAX_TEST_AMOUNT.toSharesDown(morpho.totalSupplyAssets(_id), morpho.totalSupplyShares(_id)).zeroFloorSub(
                supplyShares
            )
        );
    }

    function _boundWithdrawAssets(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 supplyBalance = morpho.expectedSupplyBalance(_marketParams, onBehalf);
        uint256 liquidity = morpho.totalSupplyAssets(_id) - morpho.totalBorrowAssets(_id);

        return bound(assets, 0, MAX_TEST_AMOUNT.min(supplyBalance).min(liquidity));
    }

    function _boundWithdrawShares(MarketParams memory _marketParams, address onBehalf, uint256 shares)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 supplyShares = morpho.supplyShares(_id, onBehalf);
        uint256 totalSupplyAssets = morpho.totalSupplyAssets(_id);

        uint256 liquidity = totalSupplyAssets - morpho.totalBorrowAssets(_id);
        uint256 liquidityShares = liquidity.toSharesDown(totalSupplyAssets, morpho.totalSupplyShares(_id));

        return bound(shares, 0, supplyShares.min(liquidityShares));
    }

    function _boundBorrowAssets(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 maxBorrow = _maxBorrow(_marketParams, onBehalf);
        uint256 borrowed = morpho.expectedBorrowBalance(_marketParams, onBehalf);
        uint256 liquidity = morpho.totalSupplyAssets(_id) - morpho.totalBorrowAssets(_id);

        return bound(assets, 0, MAX_TEST_AMOUNT.min(maxBorrow - borrowed).min(liquidity));
    }

    function _boundRepayAssets(MarketParams memory _marketParams, address onBehalf, uint256 assets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(_marketParams);
        uint256 maxRepayAssets = morpho.borrowShares(_id, onBehalf).toAssetsDown(totalBorrowAssets, totalBorrowShares);

        return bound(assets, 0, maxRepayAssets);
    }

    function _boundRepayShares(MarketParams memory _marketParams, address onBehalf, uint256 shares)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 borrowShares = morpho.borrowShares(_id, onBehalf);

        return bound(shares, 0, borrowShares);
    }

    function _boundLiquidateSeizedAssets(MarketParams memory _marketParams, address borrower, uint256 seizedAssets)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 collateral = morpho.collateral(_id, borrower);
        uint256 collateralPrice = IOracle(_marketParams.oracle).price();
        uint256 maxRepaidAssets = morpho.expectedBorrowBalance(_marketParams, borrower);
        uint256 maxSeizedAssets = maxRepaidAssets.wMulDown(_liquidationIncentive(_marketParams.lltv)).mulDivDown(
            ORACLE_PRICE_SCALE, collateralPrice
        );

        return bound(seizedAssets, 0, Math.min(collateral, maxSeizedAssets));
    }

    function _boundLiquidateRepaidShares(MarketParams memory _marketParams, address borrower, uint256 repaidShares)
        internal
        view
        returns (uint256)
    {
        Id _id = _marketParams.id();

        uint256 borrowShares = morpho.borrowShares(_id, borrower);
        uint256 collateralPrice = IOracle(_marketParams.oracle).price();
        uint256 maxRepaidAssets = morpho.collateral(_id, borrower).mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(
            _liquidationIncentive(_marketParams.lltv)
        );
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 maxRepaidShares = maxRepaidAssets.toSharesDown(totalBorrowAssets, totalBorrowShares);

        return bound(repaidShares, 0, Math.min(borrowShares, maxRepaidShares));
    }

    function _maxBorrow(MarketParams memory _marketParams, address user) internal view returns (uint256) {
        Id _id = _marketParams.id();

        uint256 collateralPrice = IOracle(_marketParams.oracle).price();

        return morpho.collateral(_id, user).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(_marketParams.lltv);
    }

    function _isHealthy(MarketParams memory _marketParams, address user) internal view returns (bool) {
        uint256 maxBorrow = _maxBorrow(_marketParams, user);
        uint256 borrowed = morpho.expectedBorrowBalance(_marketParams, user);

        return maxBorrow >= borrowed;
    }

    function _liquidationIncentive(uint256 lltv) internal pure returns (uint256) {
        return Math.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
    }

    function _accrueInterest(MarketParams memory market) internal {
        collateralToken.setBalance(address(this), 1);
        morpho.supplyCollateral(market, 1, address(this), hex"");
        morpho.withdrawCollateral(market, 1, address(this), address(10));
    }

    function neq(MarketParams memory a, MarketParams memory b) internal pure returns (bool) {
        return (Id.unwrap(a.id()) != Id.unwrap(b.id()));
    }

    function _randomCandidate(address[] memory candidates, uint256 seed) internal pure returns (address) {
        if (candidates.length == 0) return address(0);

        return candidates[seed % candidates.length];
    }

    function _removeAll(address[] memory inputs, address removed) internal pure returns (address[] memory result) {
        result = new address[](inputs.length);

        uint256 nbAddresses;
        for (uint256 i; i < inputs.length; ++i) {
            address input = inputs[i];

            if (input != removed) {
                result[nbAddresses] = input;
                ++nbAddresses;
            }
        }

        assembly {
            mstore(result, nbAddresses)
        }
    }

    function _randomNonZero(address[] memory users, uint256 seed) internal pure returns (address) {
        users = _removeAll(users, address(0));

        return _randomCandidate(users, seed);
    }
}
