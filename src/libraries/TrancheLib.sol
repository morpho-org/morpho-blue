// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IRateModel} from "../interfaces/IRateModel.sol";

import {TrancheId, Tranche, Position, TrancheShares} from "./Types.sol";
import {SharesMath} from "./SharesMath.sol";
import {PositionLib} from "./PositionLib.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library TrancheLib {
    using Math for uint256;
    using SharesMath for uint256;
    using WadRayMath for uint256;

    using PositionLib for Position;

    /// @dev Returns the amount of supply shares corresponding to the given amount of supply.
    function toSupplyShares(Tranche storage tranche, uint256 assets) internal view returns (uint256) {
        return assets.toShares(tranche.totalSupply, tranche.totalSupplyShares);
    }

    /// @dev Returns the amount of supply corresponding to the given amount of supply shares.
    function toSupplyAssets(Tranche storage tranche, uint256 shares) internal view returns (uint256) {
        return shares.toAssets(tranche.totalSupply, tranche.totalSupplyShares);
    }

    /// @dev Returns the amount of borrow shares corresponding to the given amount of debt.
    function toBorrowShares(Tranche storage tranche, uint256 assets) internal view returns (uint256) {
        return assets.toShares(tranche.totalBorrow, tranche.totalBorrowShares);
    }

    /// @dev Returns the amount of debt corresponding to the given amount of borrow shares.
    function toBorrowAssets(Tranche storage tranche, uint256 shares) internal view returns (uint256) {
        return shares.toAssets(tranche.totalBorrow, tranche.totalBorrowShares);
    }

    /// @dev Deposits the given supply to the tranche.
    function deposit(Tranche storage tranche, uint256 assets) internal returns (uint256 shares) {
        uint256 totalSupply = tranche.totalSupply;
        uint256 totalSupplyShares = tranche.totalSupplyShares;

        shares = assets.toShares(totalSupply, totalSupplyShares);

        tranche.totalSupply = totalSupply + assets;
        tranche.totalSupplyShares = totalSupplyShares + shares;
    }

    /// @dev Withdraws the given supply from the tranche, without checking for the tranche's liquidity.
    /// Note: the supply actually withdrawn is capped to the given number of supply shares remaining,
    /// so that this function satisfies the invariant: assets (output) <= assets (input).
    function withdraw(Tranche storage tranche, uint256 assets, uint256 remainingShares)
        internal
        returns (uint256, uint256, uint256)
    {
        uint256 totalSupply = tranche.totalSupply;
        uint256 totalSupplyShares = tranche.totalSupplyShares;

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

        tranche.totalSupply = totalSupply;
        tranche.totalSupplyShares = totalSupplyShares;

        return (assets, shares, remainingShares);
    }

    /// @dev Borrows the given borrow from the tranche, without checking for the tranche's liquidity.
    function borrow(Tranche storage tranche, uint256 assets) internal returns (uint256 shares) {
        uint256 totalBorrow = tranche.totalBorrow;
        uint256 totalBorrowShares = tranche.totalBorrowShares;

        shares = assets.toShares(totalBorrow, totalBorrowShares);

        tranche.totalBorrow = totalBorrow + assets;
        tranche.totalBorrowShares = totalBorrowShares + shares;
    }

    /// @dev Repays the given debt from the tranche.
    /// Note: the borrow actually repaid is capped to the number of borrow shares remaining from the position,
    /// so that this function satisfies the invariant: assets (output) <= assets (input).
    function repay(Tranche storage tranche, Position storage position, TrancheId trancheId, uint256 assets)
        internal
        returns (uint256, uint256, uint256)
    {
        TrancheShares storage trancheShares = position.getTrancheShares(trancheId);

        uint256 remainingShares = trancheShares.borrow;
        if (remainingShares == 0) return (0, 0, 0);

        uint256 totalBorrow = tranche.totalBorrow;
        uint256 totalBorrowShares = tranche.totalBorrowShares;

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

        tranche.totalBorrow = totalBorrow;
        tranche.totalBorrowShares = totalBorrowShares;

        trancheShares.borrow = remainingShares;

        if (remainingShares == 0) position.setBorrowing(trancheId, false);

        uint256 remainingBorrow = remainingShares.toAssets(totalBorrow, totalBorrowShares);

        return (assets, shares, remainingBorrow);
    }

    /// @dev Removes the given supply from the tranche.
    /// Note: the bad debt actually realized it capped to the tranche's total supply,
    /// so that this function satisfies the invariant: realized <= assets.
    function realizeBadDebt(Tranche storage tranche, uint256 assets) internal returns (uint256 realized) {
        uint256 totalSupply = tranche.totalSupply;
        uint256 newTotalSupply = totalSupply.zeroFloorSub(assets);

        unchecked {
            // Cannot underflow: newTotalSupply = max(0, totalSupply - assets) <= totalSupply.
            realized = totalSupply - newTotalSupply;
        }

        tranche.totalSupply = newTotalSupply;
    }

    /// @dev Accrues interests to the tranche.
    function accrue(Tranche storage tranche, IRateModel rateModel) internal returns (Tranche memory accrued) {
        accrued = getAccrued(tranche, rateModel);

        tranche.totalSupply = accrued.totalSupply;
        tranche.totalBorrow = accrued.totalBorrow;

        tranche.lastAccrualTimestamp = accrued.lastAccrualTimestamp;
        tranche.lastBorrowRate = accrued.lastBorrowRate;
    }

    /// @dev Virtually accrues interests to the tranche.
    function getAccrued(Tranche storage tranche, IRateModel rateModel) internal view returns (Tranche memory accrued) {
        accrued = tranche;

        uint256 lastAccrualTimestamp = tranche.lastAccrualTimestamp;
        if (lastAccrualTimestamp == 0) return accrued;

        uint256 dTimestamp = block.timestamp - lastAccrualTimestamp;
        if (dTimestamp == 0) return accrued;

        uint256 totalSupply = accrued.totalSupply;
        uint256 totalBorrow = accrued.totalBorrow;

        uint256 utilization = totalSupply > 0 ? totalBorrow.wadDiv(totalSupply) : 0;

        uint256 dBorrowRate = rateModel.dBorrowRate(utilization);

        uint256 borrowRate = tranche.lastBorrowRate + dBorrowRate * dTimestamp;
        uint256 supplyRate = borrowRate.wadMul(utilization);

        accrued.totalSupply += totalSupply.rayMul(supplyRate * dTimestamp);
        accrued.totalBorrow += totalBorrow.rayMul(borrowRate * dTimestamp);

        accrued.lastAccrualTimestamp = block.timestamp;
        accrued.lastBorrowRate = borrowRate;
    }
}

library TrancheMemLib {
    using SharesMath for uint256;

    /// @dev Returns the supply available to be borrowed or withdrawn from the tranche.
    function liquidity(Tranche memory tranche) internal pure returns (uint256) {
        return tranche.totalSupply - tranche.totalBorrow;
    }

    /// @dev Returns the amount of supply corresponding to the given amount of shares.
    function toSupplyAssets(Tranche memory tranche, TrancheShares memory shares) internal pure returns (uint256) {
        return shares.supply.toAssets(tranche.totalSupply, tranche.totalSupplyShares);
    }

    /// @dev Returns the amount of supply corresponding to the given amount of shares.
    function toBorrowAssets(Tranche memory tranche, TrancheShares memory shares) internal pure returns (uint256) {
        return shares.borrow.toAssets(tranche.totalBorrow, tranche.totalBorrowShares);
    }
}
