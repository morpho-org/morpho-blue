// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseInvariantTest.sol";

contract DynamicInvariantTest is BaseInvariantTest {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal immutable MIN_PRICE = ORACLE_PRICE_SCALE / 10;
    uint256 internal immutable MAX_PRICE = ORACLE_PRICE_SCALE * 10;

    function setUp() public virtual override {
        selectors.push(this.liquidateSeizedAssetsNoRevert.selector);
        selectors.push(this.liquidateRepaidSharesNoRevert.selector);
        selectors.push(this.setFeeNoRevert.selector);
        selectors.push(this.setPrice.selector);
        selectors.push(this.mine.selector);

        super.setUp();
    }

    /* HANDLERS */

    function setPrice(uint256 price) external {
        price = bound(price, MIN_PRICE, MAX_PRICE);

        oracle.setPrice(price);
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
