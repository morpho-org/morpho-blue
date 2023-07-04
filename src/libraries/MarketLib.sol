// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IRateModel} from "../interfaces/IRateModel.sol";

import {NB_TRANCHES, LIQUIDATION_HEALTH_FACTOR} from "./Constants.sol";
import {Market, Tranche, TrancheShares, TrancheId, Position} from "./Types.sol";
import {NotEnoughLiquidity, UnhealthyHealthFactor, HealthyHealthFactor} from "./Errors.sol";
import {TrancheLib, TrancheMemLib} from "./TrancheLib.sol";
import {TrancheIdLib} from "./TrancheIdLib.sol";
import {PositionLib} from "./PositionLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library MarketLib {
    using Math for uint256;
    using WadRayMath for uint256;

    using TrancheLib for Tranche;
    using TrancheMemLib for Tranche;
    using TrancheIdLib for TrancheId;
    using PositionLib for Position;

    function getTranche(Market storage market, TrancheId trancheId) internal view returns (Tranche storage) {
        return market.tranches[trancheId.index()];
    }

    function getPosition(Market storage market, address user) internal view returns (Position storage) {
        return market.positions[user];
    }

    function getCollateralBalance(Market storage market, address user) internal view returns (uint256) {
        return getPosition(market, user).collateral;
    }

    /// @dev Calculates the user's total weighted borrow, defined the sum of borrows from each tranche, weighted by the inverse of the tranche's liquidation LTV.
    function getWeightedBorrow(Market storage market, address user) internal view returns (uint256 total) {
        Position storage position = getPosition(market, user);

        uint256 tranchesMask = position.tranchesMask;

        for (uint256 i; i < NB_TRANCHES; ++i) {
            TrancheId trancheId = TrancheId.wrap(i);

            if (!trancheId.isBorrowing(tranchesMask)) continue;

            Tranche storage tranche = getTranche(market, trancheId);
            TrancheShares storage trancheShares = position.getTrancheShares(trancheId);

            uint256 liquidationLtv = trancheId.getLiquidationLtv();

            total += tranche.toBorrowAssets(trancheShares.borrow).wadDiv(liquidationLtv);
        }
    }

    /// @dev Calculates the health factor of the given user according to the given price of collateral quoted in debt assets.
    /// The health factor is defined as the ratio between the user's total collateral value and their total weighted borrow.
    /// This way, the user is insolvent as soon as their health factor is below the unit threshold. A user is considered safe while their health factor is above the unit threshold.
    /// Note: requires to have updated all the tranches the user is borrowing from to account for interests.
    function getHealthFactor(Market storage market, address user, uint256 price) internal view returns (uint256) {
        uint256 weightedBorrow = getWeightedBorrow(market, user);
        if (weightedBorrow == 0) return type(uint256).max;

        uint256 collateral = getCollateralBalance(market, user);
        uint256 collateralValue = collateral.wadMul(price);
        if (collateralValue == 0) return 0;

        return collateralValue.wadDiv(weightedBorrow);
    }

    function checkHealthy(Market storage market, address user, uint256 price) internal view {
        uint256 healthFactor = getHealthFactor(market, user, price);

        if (healthFactor < LIQUIDATION_HEALTH_FACTOR) revert UnhealthyHealthFactor(healthFactor);
    }

    function checkUnhealthy(Market storage market, address user, uint256 price) internal view {
        uint256 healthFactor = getHealthFactor(market, user, price);

        if (healthFactor >= LIQUIDATION_HEALTH_FACTOR) revert HealthyHealthFactor(healthFactor);
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
        Position storage _position = getPosition(market, user);
        uint256 remaining = _position.collateral;

        collaterals = Math.min(collaterals, remaining);

        unchecked {
            // Cannot underflow: collaterals = min(collaterals, remaining) <= remaining.
            remaining -= collaterals;
        }

        _position.collateral = remaining;

        return (collaterals, remaining);
    }

    /// @dev Accounts for the deposit of assets to the given user's deposit in the given tranche, accruing interests since the last time the tranche was interacted with.
    function deposit(Market storage market, TrancheId trancheId, IRateModel rateModel, uint256 assets, address user)
        internal
        returns (uint256 shares)
    {
        Tranche storage tranche = getTranche(market, trancheId);
        tranche.accrue(rateModel);

        shares = tranche.deposit(assets);

        Position storage position = getPosition(market, user);
        TrancheShares storage trancheShares = position.getTrancheShares(trancheId);

        trancheShares.supply += shares;
    }

    /// @dev Accounts for the withdrawal of assets from the given user's deposit in the given tranche, accruing interests since the last time the tranche was interacted with.
    function withdraw(Market storage market, TrancheId trancheId, IRateModel rateModel, uint256 assets, address user)
        internal
        returns (uint256, uint256)
    {
        Position storage position = getPosition(market, user);
        TrancheShares storage trancheShares = position.getTrancheShares(trancheId);

        uint256 remainingShares = trancheShares.supply;
        if (remainingShares == 0) return (0, 0);

        Tranche storage tranche = getTranche(market, trancheId);
        Tranche memory accruedTranche = tranche.accrue(rateModel);

        uint256 liquidity = accruedTranche.liquidity();
        if (liquidity < assets) revert NotEnoughLiquidity(liquidity);

        uint256 shares;
        (assets, shares, remainingShares) = tranche.withdraw(assets, remainingShares);

        trancheShares.supply = remainingShares;

        return (assets, shares);
    }

    /// @dev Accounts for the borrow of assets from the given user's debt in the given tranche, accruing interests since the last time the tranche was interacted with.
    function borrow(Market storage market, TrancheId trancheId, IRateModel rateModel, uint256 assets, address user)
        internal
        returns (uint256 shares)
    {
        Tranche storage tranche = getTranche(market, trancheId);
        Tranche memory accruedTranche = tranche.accrue(rateModel);

        uint256 liquidity = accruedTranche.liquidity();
        if (liquidity < assets) revert NotEnoughLiquidity(liquidity);

        shares = tranche.borrow(assets);

        Position storage position = getPosition(market, user);
        TrancheShares storage trancheShares = position.getTrancheShares(trancheId);

        uint256 prevShares = trancheShares.borrow;
        if (prevShares == 0) position.setBorrowing(trancheId, true);

        trancheShares.borrow = prevShares + shares;
    }

    /// @dev Accounts for the repay of assets to the given user's debt in the given tranche, accruing interests since the last time the tranche was interacted with.
    function repay(Market storage market, TrancheId trancheId, IRateModel rateModel, uint256 assets, address user)
        internal
        returns (uint256, uint256, uint256)
    {
        Position storage position = getPosition(market, user);

        Tranche storage tranche = getTranche(market, trancheId);
        tranche.accrue(rateModel);

        return tranche.repay(position, trancheId, assets);
    }

    /// @dev Accrues interests on all tranches the given user is borrowing from.
    function accrueAll(Market storage market, IRateModel rateModel, address user) internal {
        Position storage position = getPosition(market, user);

        uint256 tranchesMask = position.tranchesMask;

        for (uint256 i; i < NB_TRANCHES; ++i) {
            TrancheId trancheId = TrancheId.wrap(i);

            if (!trancheId.isBorrowing(tranchesMask)) continue;

            Tranche storage tranche = getTranche(market, trancheId);

            tranche.accrue(rateModel);
        }
    }
}
