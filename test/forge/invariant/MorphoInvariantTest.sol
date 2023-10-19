// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract MorphoInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal immutable MIN_PRICE = ORACLE_PRICE_SCALE / 10;
    uint256 internal immutable MAX_PRICE = ORACLE_PRICE_SCALE * 10;

    address internal immutable USER;

    MarketParams[] internal allMarketParams;

    constructor() {
        USER = _addrFromHashedString("User");
    }

    function setUp() public virtual override {
        _weightSelector(this.setPrice.selector, 10);
        _weightSelector(this.setFeeNoRevert.selector, 5);
        _weightSelector(this.supplyAssetsOnBehalfNoRevert.selector, 100);
        _weightSelector(this.supplySharesOnBehalfNoRevert.selector, 100);
        _weightSelector(this.withdrawAssetsOnBehalfNoRevert.selector, 50);
        _weightSelector(this.borrowAssetsOnBehalfNoRevert.selector, 75);
        _weightSelector(this.repayAssetsOnBehalfNoRevert.selector, 35);
        _weightSelector(this.repaySharesOnBehalfNoRevert.selector, 35);
        _weightSelector(this.supplyCollateralOnBehalfNoRevert.selector, 100);
        _weightSelector(this.withdrawCollateralOnBehalfNoRevert.selector, 50);
        _weightSelector(this.liquidateSeizedAssetsNoRevert.selector, 5);
        _weightSelector(this.liquidateRepaidSharesNoRevert.selector, 5);

        super.setUp();

        allMarketParams.push(marketParams);

        for (uint256 i = 2; i <= 6; ++i) {
            MarketParams memory _marketParams = MarketParams({
                loanToken: address(loanToken),
                collateralToken: address(collateralToken),
                oracle: address(oracle),
                irm: address(irm),
                lltv: MAX_TEST_LLTV / i
            });

            vm.startPrank(OWNER);
            morpho.enableLltv(_marketParams.lltv);
            morpho.createMarket(_marketParams);
            vm.stopPrank();

            allMarketParams.push(_marketParams);
        }
    }

    function _targetSenders() internal virtual override {
        _targetSender(USER);
    }

    function _randomMarket(uint256 marketSeed) internal view returns (MarketParams memory _marketParams) {
        return allMarketParams[marketSeed % allMarketParams.length];
    }

    /* SELECTED FUNCTIONS */

    function setPrice(uint256 price) external {
        price = bound(price, MIN_PRICE, MAX_PRICE);

        oracle.setPrice(price);
    }

    function setFeeNoRevert(uint256 marketSeed, uint256 newFee) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _setFeeNoRevert(_marketParams, newFee);
    }

    function supplyAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _supplyAssetsOnBehalfNoRevert(_marketParams, assets, onBehalfSeed);
    }

    function supplySharesOnBehalfNoRevert(uint256 marketSeed, uint256 shares, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _supplySharesOnBehalfNoRevert(_marketParams, shares, onBehalfSeed);
    }

    function withdrawAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed, address receiver)
        external
    {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _withdrawAssetsOnBehalfNoRevert(_marketParams, assets, onBehalfSeed, receiver);
    }

    function borrowAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed, address receiver)
        external
    {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _borrowAssetsOnBehalfNoRevert(_marketParams, assets, onBehalfSeed, receiver);
    }

    function repayAssetsOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _repayAssetsOnBehalfNoRevert(_marketParams, assets, onBehalfSeed);
    }

    function repaySharesOnBehalfNoRevert(uint256 marketSeed, uint256 shares, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _repaySharesOnBehalfNoRevert(_marketParams, shares, onBehalfSeed);
    }

    function supplyCollateralOnBehalfNoRevert(uint256 marketSeed, uint256 assets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _supplyCollateralOnBehalfNoRevert(_marketParams, assets, onBehalfSeed);
    }

    function withdrawCollateralOnBehalfNoRevert(
        uint256 marketSeed,
        uint256 assets,
        uint256 onBehalfSeed,
        address receiver
    ) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _withdrawCollateralOnBehalfNoRevert(_marketParams, assets, onBehalfSeed, receiver);
    }

    function liquidateSeizedAssetsNoRevert(uint256 marketSeed, uint256 seizedAssets, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _liquidateSeizedAssetsNoRevert(_marketParams, seizedAssets, onBehalfSeed);
    }

    function liquidateRepaidSharesNoRevert(uint256 marketSeed, uint256 repaidShares, uint256 onBehalfSeed) external {
        MarketParams memory _marketParams = _randomMarket(marketSeed);
        _liquidateRepaidSharesNoRevert(_marketParams, repaidShares, onBehalfSeed);
    }

    /* INVARIANTS */

    function invariantSupplyShares() public {
        address[] memory users = targetSenders();

        for (uint256 i; i < allMarketParams.length; ++i) {
            MarketParams memory _marketParams = allMarketParams[i];
            Id _id = _marketParams.id();

            uint256 sumSupplyShares = morpho.supplyShares(_id, FEE_RECIPIENT);
            for (uint256 j; j < users.length; ++j) {
                sumSupplyShares += morpho.supplyShares(_id, users[j]);
            }

            assertEq(sumSupplyShares, morpho.totalSupplyShares(_id), vm.toString(_marketParams.lltv));
        }
    }

    function invariantBorrowShares() public {
        address[] memory users = targetSenders();

        for (uint256 i; i < allMarketParams.length; ++i) {
            MarketParams memory _marketParams = allMarketParams[i];
            Id _id = _marketParams.id();

            uint256 sumBorrowShares;
            for (uint256 j; j < users.length; ++j) {
                sumBorrowShares += morpho.borrowShares(_id, users[j]);
            }

            assertEq(sumBorrowShares, morpho.totalBorrowShares(_id), vm.toString(_marketParams.lltv));
        }
    }

    function invariantTotalSupplyGeTotalBorrow() public {
        for (uint256 i; i < allMarketParams.length; ++i) {
            MarketParams memory _marketParams = allMarketParams[i];
            Id _id = _marketParams.id();

            assertGe(morpho.totalSupplyAssets(_id), morpho.totalBorrowAssets(_id));
        }
    }

    function invariantMorphoBalance() public {
        for (uint256 i; i < allMarketParams.length; ++i) {
            MarketParams memory _marketParams = allMarketParams[i];
            Id _id = _marketParams.id();

            assertGe(
                loanToken.balanceOf(address(morpho)) + morpho.totalBorrowAssets(_id), morpho.totalSupplyAssets(_id)
            );
        }
    }

    function invariantBadDebt() public {
        address[] memory users = targetSenders();

        for (uint256 i; i < allMarketParams.length; ++i) {
            MarketParams memory _marketParams = allMarketParams[i];
            Id _id = _marketParams.id();

            for (uint256 j; j < users.length; ++j) {
                address user = users[j];

                if (morpho.collateral(_id, user) == 0) {
                    assertEq(
                        morpho.borrowShares(_id, user),
                        0,
                        string.concat(vm.toString(_marketParams.lltv), ":", vm.toString(user))
                    );
                }
            }
        }
    }
}
