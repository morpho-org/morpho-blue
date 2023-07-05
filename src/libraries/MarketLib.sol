// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IRateModel} from "../interfaces/IRateModel.sol";

import {NB_TRANCHES, LIQUIDATION_HEALTH_FACTOR} from "./Constants.sol";
import {Market, MarketKey, MarketState, MarketShares, Position} from "./Types.sol";
import {NotEnoughLiquidity} from "./Errors.sol";
import {MarketStateLib, MarketStateMemLib} from "./MarketStateLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library MarketLib {
    using Math for uint256;
    using WadRayMath for uint256;

    using MarketStateLib for MarketState;
    using MarketStateMemLib for MarketState;

    function getPosition(Market storage market, address user) internal view returns (Position storage) {
        return market.positions[user];
    }

    /// @dev Calculates the LTV of the given user according to the given price of collateral quoted in debt assets.
    function getLtv(Market storage market, address user, uint256 price) internal view returns (uint256) {
        Position storage position = getPosition(market, user);

        uint256 borrowValue = market.state.toBorrowAssets(position.shares.borrow);
        if (borrowValue == 0) return 0;

        uint256 collateralValue = position.collateral.wadMul(price);
        if (collateralValue == 0) return type(uint256).max;

        return borrowValue.wadDiv(collateralValue);
    }

    /// @dev Accounts for the deposit of collateral to the given user's collateral deposit.
    /// Note: does not accrue any tranche because it's not required.
    function depositCollateral(Market storage market, uint256 collaterals, address user) internal {
        getPosition(market, user).collateral += collaterals;
    }

    /// @dev Accounts for the withdrawal of collateral from the given user's collateral deposit.
    /// Note: does not accrue any tranche because it's not required.
    function withdrawCollateral(Market storage market, uint256 collaterals, address user)
        internal
        returns (uint256, uint256)
    {
        Position storage position = getPosition(market, user);
        uint256 remaining = position.collateral;

        collaterals = Math.min(collaterals, remaining);

        unchecked {
            // Cannot underflow: collaterals = min(collaterals, remaining) <= remaining.
            remaining -= collaterals;
        }

        position.collateral = remaining;

        return (collaterals, remaining);
    }

    /// @dev Accounts for the deposit of assets to the given user's deposit in the given tranche, accruing interests since the last time the tranche was interacted with.
    function deposit(Market storage market, MarketKey calldata marketKey, uint256 assets, address user)
        internal
        returns (uint256 shares)
    {
        market.state.accrue(marketKey);

        shares = market.state.deposit(assets);

        Position storage position = getPosition(market, user);

        position.shares.supply += shares;
    }

    /// @dev Accounts for the withdrawal of assets from the given user's deposit in the given tranche, accruing interests since the last time the tranche was interacted with.
    function withdraw(Market storage market, MarketKey calldata marketKey, uint256 assets, address user)
        internal
        returns (uint256, uint256)
    {
        Position storage position = getPosition(market, user);
        MarketShares storage marketShares = position.shares;

        uint256 remainingShares = marketShares.supply;
        if (remainingShares == 0) return (0, 0);

        MarketState memory accruedState = market.state.accrue(marketKey);

        uint256 liquidity = accruedState.liquidity();
        if (liquidity < assets) revert NotEnoughLiquidity(liquidity);

        uint256 shares;
        (assets, shares, remainingShares) = market.state.withdraw(assets, remainingShares);

        marketShares.supply = remainingShares;

        return (assets, shares);
    }

    /// @dev Accounts for the borrow of assets from the given user's debt in the given tranche, accruing interests since the last time the tranche was interacted with.
    function borrow(Market storage market, MarketKey calldata marketKey, uint256 assets, address user)
        internal
        returns (uint256 shares)
    {
        MarketState memory accruedState = market.state.accrue(marketKey);

        uint256 liquidity = accruedState.liquidity();
        if (liquidity < assets) revert NotEnoughLiquidity(liquidity);

        shares = market.state.borrow(assets);

        Position storage position = getPosition(market, user);

        position.shares.borrow += shares;
    }

    /// @dev Accounts for the repay of assets to the given user's debt in the given tranche, accruing interests since the last time the tranche was interacted with.
    function repay(Market storage market, MarketKey calldata marketKey, uint256 assets, address user)
        internal
        returns (uint256, uint256, uint256)
    {
        market.state.accrue(marketKey);

        Position storage position = getPosition(market, user);

        return market.state.repay(position.shares, assets);
    }

    function realizeBadDebt(Market storage market, address user, uint256 remainingBorrow) internal {
        Position storage position = getPosition(market, user);

        position.shares.borrow = 0;
        market.state.totalBorrow -= remainingBorrow;

        market.state.realizeBadDebt(remainingBorrow);
    }
}
