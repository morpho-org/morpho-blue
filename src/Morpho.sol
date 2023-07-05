// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "./interfaces/IMorpho.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IERC3156xFlashLiquidator} from "./interfaces/IERC3156xFlashLiquidator.sol";

import {NB_TRANCHES, LIQUIDATION_HEALTH_FACTOR, FLASH_LIQUIDATOR_SUCCESS_HASH} from "./libraries/Constants.sol";
import {MarketKey, Market, MarketState, MarketShares, Position} from "./libraries/Types.sol";
import {CannotBorrow, CannotWithdrawCollateral, TooMuchSeized, Unhealthy, Healthy} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketKeyLib} from "./libraries/MarketKeyLib.sol";
import {MarketStateLib} from "./libraries/MarketStateLib.sol";

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
    using MarketKeyLib for MarketKey;
    using MarketStateLib for MarketState;

    using Permit2Lib for ERC20;
    using SafeTransferLib for ERC20;

    constructor(address initialOwner) MarketBase(initialOwner) {}

    /* EXTERNAL */

    /// @notice Returns the given market's tranche based on its id.
    function marketAt(MarketKey calldata marketKey) external view returns (MarketState memory accrued) {
        (, Market storage market) = _market(marketKey);

        accrued = market.state.getAccrued(marketKey);
    }

    /// @notice Returns the given user's position on the given tranche.
    /// Note: does not return balances because it requires virtually accruing interests in the given tranche.
    function sharesOf(MarketKey calldata marketKey, address user) external view returns (Position memory position) {
        (, Market storage market) = _market(marketKey);

        position = market.getPosition(user);
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

        _checkHealthy(market, onBehalf, price, marketKey.liquidationLtv); // PERF: market.positions[onBehalf].collateral is SLOAD but is already loaded as second return parameter of market.withdrawCollateral

        // Transfer tokens last to prevent ERC777 re-entrancy vulnerability.
        marketKey.collateral.safeTransfer(receiver, collaterals);
    }

    function deposit(MarketKey calldata marketKey, uint256 assets, address onBehalf)
        external
        returns (uint256 shares)
    {
        // Transfer tokens first to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.transferFrom2(msg.sender, address(this), assets);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        shares = market.deposit(marketKey, assets, onBehalf);

        emit Events.Deposit(marketId, msg.sender, onBehalf, assets, shares);
    }

    // TODO: replace `assets` with `shares` for precise repay (ERC4626-like). Rename `withdraw` to `redeem`.
    // Requires to calculate the assets based on the shares because we still need to transfer tokens before accounting for the repay to avoid re-entrancy vulnerability.
    function withdraw(MarketKey calldata marketKey, uint256 assets, address onBehalf, address receiver)
        external
        returns (uint256 shares)
    {
        // Checks whether the sender has enough allowance to withdraw on behalf.
        _spendAllowance(onBehalf, msg.sender, assets);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        (assets, shares) = market.withdraw(marketKey, assets, onBehalf);

        emit Events.Withdraw(marketId, msg.sender, onBehalf, receiver, assets, shares);

        // Transfer tokens last to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.safeTransfer(receiver, assets);
    }

    function borrow(MarketKey calldata marketKey, uint256 assets, address onBehalf, address receiver)
        external
        returns (uint256 shares)
    {
        // Checks whether the sender has enough allowance to borrow on behalf.
        _spendAllowance(onBehalf, msg.sender, assets);

        (uint256 price, bool canBorrow,) = IOracle(marketKey.oracle).price();
        if (!canBorrow) revert CannotBorrow();

        (bytes32 marketId, Market storage market) = _market(marketKey);

        shares = market.borrow(marketKey, assets, onBehalf);

        emit Events.Borrow(marketId, msg.sender, onBehalf, receiver, assets, shares);

        _checkHealthy(market, onBehalf, price, marketKey.liquidationLtv);

        // console.log("borrow", TrancheId.unwrap(, assets);

        // Transfer tokens last to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.safeTransfer(receiver, assets);
    }

    // TODO: replace `assets` with `shares` for precise repay (ERC4626-like).
    // Requires to calculate the assets based on the shares because we still need to transfer tokens before accounting for the repay to avoid re-entrancy vulnerability.
    function repay(MarketKey calldata marketKey, uint256 assets, address onBehalf) external returns (uint256 shares) {
        // Transfer tokens first to prevent ERC777 re-entrancy vulnerability.
        marketKey.asset.transferFrom2(msg.sender, address(this), assets);

        (bytes32 marketId, Market storage market) = _market(marketKey);

        (assets, shares,) = market.repay(marketKey, assets, onBehalf);

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

        _checkUnhealthy(market, borrower, price, marketKey.liquidationLtv);

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

        uint256 remainingBorrow;
        (repaid,, remainingBorrow) = market.repay(marketKey, debt, borrower);

        // TODO: reverts if price == 0
        uint256 seized = repaid.wadDiv(price); // TODO: limit seized so LTV goes back to 25% below LLTV?
        uint256 maxSeized = seized + marketKey.getLiquidationBonus(seized); // TODO: can overflow if price too low

        if (maxSeized < collateral) {
            // Liquidator asked for too much collateral in exchange for the debt actually repaid.
            revert TooMuchSeized(maxSeized);
        }

        emit Events.Liquidation(marketId, msg.sender, borrower, address(liquidator), receiver, repaid, collateral);

        uint256 collateralValue = remainingCollateral.wadMul(price);
        if (remainingBorrow <= collateralValue) return (repaid, returnData);

        // The borrower's position now holds bad debt: its collateral is not worth enough to cover its debt.
        // This bad debt must be realized now, or future lenders may provide liquidity to allow past lenders to withdraw.
        // TODO: liquidators are not incentivized to realize some bad debt because of gas cost

        market.realizeBadDebt(borrower, remainingBorrow);
    }

    /* INTERNAL */

    function _checkHealthy(Market storage market, address user, uint256 price, uint256 liquidationLtv) internal view {
        uint256 ltv = market.getLtv(user, price);

        if (ltv >= liquidationLtv) revert Unhealthy(ltv);
    }

    function _checkUnhealthy(Market storage market, address user, uint256 price, uint256 liquidationLtv)
        internal
        view
    {
        uint256 ltv = market.getLtv(user, price);

        if (ltv < liquidationLtv) revert Healthy(ltv);
    }
}
