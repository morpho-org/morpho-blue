// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IRateModel} from "../interfaces/IRateModel.sol";

import {MarketState, MarketShares} from "./Types.sol";
import {SharesMath} from "./SharesMath.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library MarketStateLib {
    using Math for uint256;
    using SharesMath for uint256;
    using WadRayMath for uint256;

    /// @dev Returns the amount of supply shares corresponding to the given amount of supply.
    function toSupplyShares(MarketState storage state, uint256 assets) internal view returns (uint256) {
        return assets.toShares(state.totalSupply, state.totalSupplyShares);
    }

    /// @dev Returns the amount of supply corresponding to the given amount of supply shares.
    function toSupplyAssets(MarketState storage state, uint256 shares) internal view returns (uint256) {
        return shares.toAssets(state.totalSupply, state.totalSupplyShares);
    }

    /// @dev Returns the amount of borrow shares corresponding to the given amount of debt.
    function toBorrowShares(MarketState storage state, uint256 assets) internal view returns (uint256) {
        return assets.toShares(state.totalBorrow, state.totalBorrowShares);
    }

    /// @dev Returns the amount of debt corresponding to the given amount of borrow shares.
    function toBorrowAssets(MarketState storage state, uint256 shares) internal view returns (uint256) {
        return shares.toAssets(state.totalBorrow, state.totalBorrowShares);
    }

    /// @dev Deposits the given supply to the state.
    function deposit(MarketState storage state, uint256 assets) internal returns (uint256 shares) {
        uint256 totalSupply = state.totalSupply;
        uint256 totalSupplyShares = state.totalSupplyShares;

        shares = assets.toShares(totalSupply, totalSupplyShares);

        state.totalSupply = totalSupply + assets;
        state.totalSupplyShares = totalSupplyShares + shares;
    }

    /// @dev Withdraws the given supply from the state, without checking for the state's liquidity.
    /// Note: the supply actually withdrawn is capped to the given number of supply shares remaining,
    /// so that this function satisfies the invariant: assets (output) <= assets (input).
    function withdraw(MarketState storage state, uint256 assets, uint256 remainingShares)
        internal
        returns (uint256, uint256, uint256)
    {
        uint256 totalSupply = state.totalSupply;
        uint256 totalSupplyShares = state.totalSupplyShares;

        uint256 shares = assets.toShares(totalSupply, totalSupplyShares);

        if (shares > remainingShares) {
            shares = remainingShares;
            assets = shares.toAssets(totalSupply, totalSupplyShares);
        }

        unchecked {
            // Cannot underflow: assets <= totalSupply invariant from `toAssets`.
            totalSupply -= assets;
            totalSupplyShares -= shares;
            // Cannot underflow: shares = min(shares, remainingShares) <= remainingShares checked above.
            remainingShares -= shares;
        }

        state.totalSupply = totalSupply;
        state.totalSupplyShares = totalSupplyShares;

        return (assets, shares, remainingShares);
    }

    /// @dev Borrows the given borrow from the state, without checking for the state's liquidity.
    function borrow(MarketState storage state, uint256 assets) internal returns (uint256 shares) {
        uint256 totalBorrow = state.totalBorrow;
        uint256 totalBorrowShares = state.totalBorrowShares;

        shares = assets.toShares(totalBorrow, totalBorrowShares);

        state.totalBorrow = totalBorrow + assets;
        state.totalBorrowShares = totalBorrowShares + shares;
    }

    /// @dev Repays the given debt from the state.
    /// Note: the borrow actually repaid is capped to the number of borrow shares remaining from the position,
    /// so that this function satisfies the invariant: assets (output) <= assets (input).
    function repay(MarketState storage state, MarketShares storage marketShares, uint256 assets)
        internal
        returns (uint256, uint256, uint256)
    {
        uint256 remainingShares = marketShares.borrow;
        if (remainingShares == 0) return (0, 0, 0);

        uint256 totalBorrow = state.totalBorrow;
        uint256 totalBorrowShares = state.totalBorrowShares;

        uint256 shares = assets.toShares(totalBorrow, totalBorrowShares);

        if (shares > remainingShares) {
            shares = remainingShares;
            assets = shares.toAssets(totalBorrow, totalBorrowShares);
        }

        unchecked {
            // Cannot underflow: assets <= totalBorrow invariant from `toAssets`.
            totalBorrow -= assets;
            totalBorrowShares -= shares;
            // Cannot underflow: shares = min(shares, remainingShares) <= remainingShares checked above.
            remainingShares -= shares;
        }

        state.totalBorrow = totalBorrow;
        state.totalBorrowShares = totalBorrowShares;

        marketShares.borrow = remainingShares;

        uint256 remainingBorrow = remainingShares.toAssets(totalBorrow, totalBorrowShares);

        return (assets, shares, remainingBorrow);
    }

    /// @dev Removes the given supply from the state.
    /// Note: the bad debt actually realized it capped to the state's total supply,
    /// so that this function satisfies the invariant: realized <= assets.
    function realizeBadDebt(MarketState storage state, uint256 assets) internal returns (uint256 realized) {
        uint256 totalSupply = state.totalSupply;
        uint256 newTotalSupply = totalSupply.zeroFloorSub(assets);

        unchecked {
            // Cannot underflow: newTotalSupply = max(0, totalSupply - assets) <= totalSupply.
            realized = totalSupply - newTotalSupply;
        }

        state.totalSupply = newTotalSupply;
    }

    /// @dev Accrues interests to the state.
    function accrue(MarketState storage state, IRateModel rateModel) internal returns (MarketState memory accrued) {
        accrued = getAccrued(state, rateModel);

        state.totalSupply = accrued.totalSupply;
        state.totalBorrow = accrued.totalBorrow;

        state.lastAccrualTimestamp = accrued.lastAccrualTimestamp;
        state.lastBorrowRate = accrued.lastBorrowRate;
    }

    /// @dev Virtually accrues interests to the state.
    function getAccrued(MarketState storage state, IRateModel rateModel)
        internal
        view
        returns (MarketState memory accrued)
    {
        accrued = state;

        uint256 lastAccrualTimestamp = state.lastAccrualTimestamp;
        if (lastAccrualTimestamp == 0) return accrued;

        uint256 dTimestamp = block.timestamp - lastAccrualTimestamp;
        if (dTimestamp == 0) return accrued;

        uint256 totalSupply = accrued.totalSupply;
        uint256 totalBorrow = accrued.totalBorrow;

        uint256 utilization = totalSupply > 0 ? totalBorrow.wadDiv(totalSupply) : 0;

        uint256 dBorrowRate = rateModel.dBorrowRate(utilization);

        uint256 borrowRate = state.lastBorrowRate + dBorrowRate * dTimestamp;
        uint256 supplyRate = borrowRate.wadMul(utilization);

        accrued.totalSupply += totalSupply.rayMul(supplyRate * dTimestamp);
        accrued.totalBorrow += totalBorrow.rayMul(borrowRate * dTimestamp);

        accrued.lastAccrualTimestamp = block.timestamp;
        accrued.lastBorrowRate = borrowRate;
    }
}

library MarketStateMemLib {
    using SharesMath for uint256;

    /// @dev Returns the supply available to be borrowed or withdrawn from the state.
    function liquidity(MarketState memory state) internal pure returns (uint256) {
        return state.totalSupply - state.totalBorrow;
    }

    /// @dev Returns the amount of supply corresponding to the given amount of shares.
    function toSupplyAssets(MarketState memory state, MarketShares memory shares) internal pure returns (uint256) {
        return shares.supply.toAssets(state.totalSupply, state.totalSupplyShares);
    }

    /// @dev Returns the amount of supply corresponding to the given amount of shares.
    function toBorrowAssets(MarketState memory state, MarketShares memory shares) internal pure returns (uint256) {
        return shares.borrow.toAssets(state.totalBorrow, state.totalBorrowShares);
    }
}
