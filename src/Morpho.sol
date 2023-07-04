// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "./interfaces/IMorpho.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IERC3156xFlashLiquidator} from "./interfaces/IERC3156xFlashLiquidator.sol";

import {NB_TRANCHES, LIQUIDATION_HEALTH_FACTOR, FLASH_LIQUIDATOR_SUCCESS_HASH} from "./libraries/Constants.sol";
import {MarketKey, Market, Tranche, TrancheShares, TrancheId, Position} from "./libraries/Types.sol";
import {CannotBorrow, CannotWithdrawCollateral, TooMuchSeized} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {TrancheLib} from "./libraries/TrancheLib.sol";
import {PositionLib} from "./libraries/PositionLib.sol";
import {TrancheIdLib} from "./libraries/TrancheIdLib.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {Permit2Lib} from "@permit2/libraries/Permit2Lib.sol";

import {MarketBase} from "./MarketBase.sol";
import {AllowanceBase} from "./AllowanceBase.sol";
import {ERC2330} from "@morpho-utils/ERC2330.sol";
import {ERC3156xFlashLender} from "@morpho-utils/ERC3156xFlashLender.sol";

// import "hardhat/console.sol";

contract Morpho is IMorpho, MarketBase, AllowanceBase, ERC3156xFlashLender, ERC2330 {
    using WadRayMath for uint256;

    using MarketLib for Market;

    using TrancheIdLib for TrancheId;
    using TrancheLib for Tranche;
    using PositionLib for Position;

    using Permit2Lib for ERC20;
    using SafeTransferLib for ERC20;

    constructor(address initialOwner) MarketBase(initialOwner) {}

    /* EXTERNAL */

    /// @notice Returns the given market's tranche based on its id.
    function trancheAt(MarketKey calldata marketKey, TrancheId trancheId)
        external
        view
        returns (Tranche memory accrued)
    {
        (, Market storage market) = _market(marketKey);

        Tranche storage tranche = market.getTranche(trancheId);

        accrued = tranche.getAccrued(marketKey.rateModel);
    }

    /// @notice Returns the given user's position on the given tranche.
    /// Note: does not return balances because it requires virtually accruing interests in the given tranche.
    function sharesOf(MarketKey calldata marketKey, TrancheId trancheId, address user)
        external
        view
        returns (uint256 collateral, TrancheShares memory shares)
    {
        (, Market storage market) = _market(marketKey);

        collateral = market.getCollateralBalance(user);

        Position storage position = market.getPosition(user);

        shares = position.getTrancheShares(trancheId);
    }

    function depositCollateral(MarketKey calldata marketKey, uint256 collaterals, address onBehalf) external {
        // Transfer tokens first to prevent ERC777 re-entrancy vulnerability.
        marketKey.collateral.transferFrom2(msg.sender, address(this), collaterals);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        market.depositCollateral(collaterals, onBehalf);

        emit Events.CollateralDeposit(marketId, msg.sender, onBehalf, collaterals);
    }

    function withdrawCollateral(MarketKey calldata marketKey, uint256 collaterals, address onBehalf, address receiver)
        external
    {
        // Checks whether the sender has enough allowance to withdraw collateral on behalf.
        _spendAllowance(onBehalf, msg.sender, collaterals);

        (uint256 price,, bool canWithdrawCollateral) = IOracle(marketKey.oracle).price();
        if (!canWithdrawCollateral) revert CannotWithdrawCollateral();

        (bytes32 marketId, Market storage market) = _market(marketKey);

        (collaterals,) = market.withdrawCollateral(collaterals, onBehalf);

        emit Events.CollateralWithdraw(marketId, msg.sender, onBehalf, receiver, collaterals);

        // Accrue interests on all tranches the user is borrowing from to use the most up-to-date health factor.
        market.accrueAll(marketKey.rateModel, onBehalf);
        market.checkHealthy(onBehalf, price); // PERF: market.positions[onBehalf].collateral is SLOAD but is already loaded as second return parameter of market.withdrawCollateral

        // Transfer tokens last to prevent ERC777 re-entrancy vulnerability.
        marketKey.collateral.safeTransfer(receiver, collaterals);
    }

    function deposit(MarketKey calldata marketKey, TrancheId trancheId, uint256 assets, address onBehalf)
        external
        returns (uint256 shares)
    {
        // Transfer tokens first to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.transferFrom2(msg.sender, address(this), assets);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        shares = market.deposit(trancheId, marketKey.rateModel, assets, onBehalf);

        emit Events.Deposit(marketId, msg.sender, onBehalf, assets, shares);
    }

    // TODO: replace `assets` with `shares` for precise repay (ERC4626-like). Rename `withdraw` to `redeem`.
    // Requires to calculate the assets based on the shares because we still need to transfer tokens before accounting for the repay to avoid re-entrancy vulnerability.
    function withdraw(
        MarketKey calldata marketKey,
        TrancheId trancheId,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external returns (uint256 shares) {
        // Checks whether the sender has enough allowance to withdraw on behalf.
        _spendAllowance(onBehalf, msg.sender, assets);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        (assets, shares) = market.withdraw(trancheId, marketKey.rateModel, assets, onBehalf);

        emit Events.Withdraw(marketId, msg.sender, onBehalf, receiver, assets, shares);

        // Transfer tokens last to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.safeTransfer(receiver, assets);
    }

    function borrow(
        MarketKey calldata marketKey,
        TrancheId trancheId,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external returns (uint256 shares) {
        // Checks whether the sender has enough allowance to borrow on behalf.
        _spendAllowance(onBehalf, msg.sender, assets);

        (uint256 price, bool canBorrow,) = IOracle(marketKey.oracle).price();
        if (!canBorrow) revert CannotBorrow();

        (bytes32 marketId, Market storage market) = _market(marketKey);

        shares = market.borrow(trancheId, marketKey.rateModel, assets, onBehalf);

        emit Events.Borrow(marketId, msg.sender, onBehalf, receiver, assets, shares);

        // Accrue interests on all tranches the user is borrowing from to use the most up-to-date health factor.
        market.accrueAll(marketKey.rateModel, onBehalf);
        market.checkHealthy(onBehalf, price);

        // console.log("borrow", TrancheId.unwrap(trancheId), assets);

        // Transfer tokens last to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.safeTransfer(receiver, assets);
    }

    // TODO: replace `assets` with `shares` for precise repay (ERC4626-like).
    // Requires to calculate the assets based on the shares because we still need to transfer tokens before accounting for the repay to avoid re-entrancy vulnerability.
    function repay(MarketKey calldata marketKey, TrancheId trancheId, uint256 assets, address onBehalf)
        external
        returns (uint256 shares)
    {
        // Transfer tokens first to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.transferFrom2(msg.sender, address(this), assets);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        (assets, shares,) = market.repay(trancheId, marketKey.rateModel, assets, onBehalf);

        emit Events.Repay(marketId, msg.sender, onBehalf, assets, shares);
    }

    function liquidate(
        MarketKey calldata marketKey,
        address borrower,
        uint256 debt,
        uint256 collateral,
        address receiver,
        IERC3156xFlashLiquidator liquidator,
        bytes calldata data
    ) external returns (uint256 repaid, bytes memory returnData) {
        (uint256 price,, bool canWithdrawCollateral) = IOracle(marketKey.oracle).price();
        if (!canWithdrawCollateral) revert CannotWithdrawCollateral();

        (bytes32 marketId, Market storage market) = _market(marketKey);

        market.accrueAll(marketKey.rateModel, borrower);
        market.checkUnhealthy(borrower, price);

        uint256 remainingCollateral;
        (collateral, remainingCollateral) = market.withdrawCollateral(collateral, borrower);

        // Transfer collateral tokens after withdrawal accounting to prevent ERC777 re-entrancy vulnerability.
        marketKey.collateral.safeTransfer(receiver, collateral);

        if (address(liquidator) != address(0)) {
            bytes32 successHash;
            (successHash, returnData) =
                liquidator.onLiquidation(msg.sender, marketKey, borrower, debt, collateral, data);

            if (successHash != FLASH_LIQUIDATOR_SUCCESS_HASH) revert InvalidSuccessHash(successHash);

            // Transfer debt tokens before repay accounting to prevent ERC777 re-entrancy vulnerability.
            marketKey.asset.transferFrom2(address(liquidator), address(this), debt);
        } else {
            marketKey.asset.transferFrom2(msg.sender, address(this), debt);
        }

        Position storage position = market.getPosition(borrower);

        uint256 tranchesMask = position.tranchesMask;
        // console.log("tranchesMask", tranchesMask);

        uint256 left = debt;
        uint256 maxSeized;
        uint256 totalRemainingBorrow;
        uint256[NB_TRANCHES] memory remainingBorrow;
        for (uint256 i; i < NB_TRANCHES; ++i) {
            TrancheId trancheId = TrancheId.wrap(i);

            if (!trancheId.isBorrowing(tranchesMask)) continue;

            Tranche storage tranche = market.getTranche(trancheId); // Tranche is already accrued.

            (uint256 trancheRepaid,, uint256 trancheBorrow) = tranche.repay(position, trancheId, left);
            remainingBorrow[i] = trancheBorrow;
            totalRemainingBorrow += trancheBorrow;

            unchecked {
                // Cannot underflow: trancheRepaid <= left invariant from `tranche.repay`.
                left -= trancheRepaid;
            }

            // TODO: reverts if price == 0
            uint256 trancheSeized = trancheRepaid.wadDiv(price); // TODO: limit seized so LTV goes back to 25% below LLTV?
            maxSeized += trancheSeized + trancheId.getLiquidationBonus(trancheSeized); // TODO: can overflow if price too low

            // console.log("repaid", TrancheId.unwrap(trancheId), trancheSeized);
        }

        if (maxSeized < collateral) {
            // Liquidator asked for too much collateral in exchange for the debt actually repaid.
            revert TooMuchSeized(maxSeized);
        }

        unchecked {
            // Cannot underflow: 0 <= left and left was initialized to debt then always decreased.
            repaid = debt - left;
        }

        // console.log("liquidated", repaid, collateral);

        emit Events.Liquidation(marketId, msg.sender, borrower, address(liquidator), receiver, repaid, collateral);

        uint256 collateralValue = remainingCollateral.wadMul(price);
        if (totalRemainingBorrow <= collateralValue) return (repaid, returnData);

        // The borrower's position now holds bad debt: its collateral is not worth enough to cover its debt.
        // This bad debt must be realized now, or future lenders may provide liquidity to allow past lenders to withdraw.
        // TODO: liquidators are not incentivized to realize some bad debt because of gas cost

        for (uint256 i; i < NB_TRANCHES; ++i) {
            uint256 trancheBorrow = remainingBorrow[i];

            if (trancheBorrow == 0) continue;

            TrancheId borrowTrancheId = TrancheId.wrap(i);

            Tranche storage borrowTranche = market.getTranche(borrowTrancheId);

            borrowTranche.totalBorrow -= trancheBorrow;

            TrancheShares storage trancheShares = position.getTrancheShares(borrowTrancheId);

            trancheShares.borrow = 0;
            position.setBorrowing(borrowTrancheId, false);

            for (uint256 j = i; j < NB_TRANCHES; ++j) {
                TrancheId supplyTrancheId = TrancheId.wrap(j);

                Tranche storage supplyTranche = market.getTranche(supplyTrancheId);
                uint256 realized = supplyTranche.realizeBadDebt(trancheBorrow);

                unchecked {
                    // Cannot underflow: realized <= trancheBorrow invariant from `supplyTranche.realizeBadDebt`.
                    trancheBorrow -= realized;
                }

                if (trancheBorrow == 0) break;
            }
        }
    }
}
