// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/// @title Errors
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing errors used in Morpho.
library Errors {
    /// @notice Thrown when interacting with a market that is not created.
    error MarketNotCreated();

    /// @notice Thrown when creating a market that is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when choosing a tranche that is not created.
    error TrancheNotCreated();

    /// @notice Thrown when an user tries to supply in two differents tranches.
    error UserInAnotherTranche();

    /// @notice Thrown when an user tries to change to the same tranches.
    error UserAlreadyInTheTranche();

    /// @notice Thrown when an user tries to withdraw too much liquidity.
    error NotEnoughLiquidityToWithdraw();

    /// @notice Thrown when an user tries to change tranche.
    error NotEnoughLiquidityToChangeTranche();

    /// @notice Thrown when an user tries to borrow too much liquidity.
    error NotEnoughLiquidityToBorrow();

    /// @notice Thrown when an user tries to withdraw to a too low health factor.
    error HealthFactorTooLow();

    /// @notice Thrown when an amount is zero.
    error AmountIsZero();

    /// @notice Thrown when a liquidation is trid on healthy user.
    error LiquidationNotAuthorized();

    /// @notice Thrown when the manager is not approved by the delegator.
    error PermissionDenied();

    /// @notice Thrown when the s part of the ECDSA signature is invalid.
    error InvalidValueS();

    /// @notice Thrown when the v part of the ECDSA signature is invalid.
    error InvalidValueV();

    /// @notice Thrown when the signatory of the ECDSA signature is invalid.
    error InvalidSignatory();

    /// @notice Thrown when the nonce is invalid.
    error InvalidNonce();

    /// @notice Thrown when the signature is expired
    error SignatureExpired();

    /// @notice Thrown when an address to try to realize bad debt that doesn't exist.
    error NoBadDebt();

    /// @notice Thrown when supply is paused for the asset.
    error SupplyIsPaused();

    /// @notice Thrown when supply collateral is paused for the asset.
    error SupplyCollateralIsPaused();

    /// @notice Thrown when borrow is paused for the asset.
    error BorrowIsPaused();

    /// @notice Thrown when repay is paused for the asset.
    error RepayIsPaused();

    /// @notice Thrown when withdraw is paused for the asset.
    error WithdrawIsPaused();

    /// @notice Thrown when withdraw collateral is paused for the asset.
    error WithdrawCollateralIsPaused();

    /// @notice Thrown when liquidate is paused for the collateral asset.
    error LiquidateCollateralIsPaused();

    /// @notice Thrown when liquidate is paused for the borrow asset
    error LiquidateBorrowIsPaused();
}
