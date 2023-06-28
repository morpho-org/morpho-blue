// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

library Events {
    /// @notice Emitted when a supply happens.
    /// @param from The address of the user supplying the funds.
    /// @param onBehalf The address of the user on behalf of which the position is created.
    /// @param pool The address of the pool where the user supplied.
    /// @param amount The amount of `underlying` asset supplied.
    /// @param trancheNumber The tranche in which the liquidity was supplied.
    event Supplied(
        address indexed from, address indexed onBehalf, address indexed pool, uint256 amount, uint256 trancheNumber
    );

    /// @notice Emitted when a supply collateral happens.
    /// @param from The address of the user supplying the funds.
    /// @param onBehalf The address of the user on behalf of which the position is created.
    /// @param pool The address of the pool where the user supplied.
    /// @param amount The amount of collateral asset supplied.
    /// @param trancheNumber The tranche of the borrower.
    event CollateralSupplied(
        address indexed from, address indexed onBehalf, address indexed pool, uint256 amount, uint256 trancheNumber
    );

    /// @notice Emitted when a borrow happens.
    /// @param caller The address of the caller.
    /// @param onBehalf The address of the user on behalf of which the position is created.
    /// @param receiver The address of the user receiving the funds.
    /// @param pool The address of the pool where the user borrowed.
    /// @param amount The amount of `underlying` asset borrowed.
    /// @param trancheNumber The tranche in which the liquidity was borrowed.
    event Borrowed(
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        address indexed pool,
        uint256 amount,
        uint256 trancheNumber
    );

    /// @notice Emitted when a repay happens.
    /// @param repayer The address of the user repaying the debt.
    /// @param onBehalf The address of the user on behalf of which the position is modified.
    /// @param pool The address of the pool where the user repaid.
    /// @param amount The amount of `underlying` asset repaid.
    /// @param trancheNumber The tranche in which the liquidity was repaid.
    event Repaid(
        address indexed repayer, address indexed onBehalf, address indexed pool, uint256 amount, uint256 trancheNumber
    );

    /// @notice Emitted when a withdraw happens.
    /// @param caller The address of the caller.
    /// @param onBehalf The address of the user on behalf of which the position is modified.
    /// @param receiver The address of the user receiving the funds.
    /// @param pool The address of the pool asset withdrawn.
    /// @param amount The amount of `underlying` asset withdrawn.
    /// @param trancheNumber The tranche in which the liquidity was withdrawn.
    event Withdrawn(
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        address indexed pool,
        uint256 amount,
        uint256 trancheNumber
    );

    /// @notice Emitted when a withdraw collateral happens.
    /// @param caller The address of the caller.
    /// @param onBehalf The address of the user on behalf of which the position is modified.
    /// @param receiver The address of the user receiving the funds.
    /// @param underlying The address of the underlying asset withdrawn.
    /// @param amount The amount of `underlying` asset withdrawn.
    event CollateralWithdrawn(
        address caller, address indexed onBehalf, address indexed receiver, address indexed underlying, uint256 amount
    );

    /// @notice Emitted when a liquidate happens.
    /// @param liquidator The address of the liquidator.
    /// @param borrower The address of the borrower that was liquidated.
    /// @param pool The address of the pool of the liquidation.
    /// @param token The address of the underlying asset borrowed being repaid.
    /// @param amountLiquidated The amount of `underlyingBorrowed` repaid.
    /// @param collateral The address of the collateral underlying seized.
    /// @param amountSeized The amount of `underlyingCollateral` seized.
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed pool,
        address token,
        uint256 amountLiquidated,
        address collateral,
        uint256 amountSeized
    );

    /// @notice Emitted when a `manager` is approved or unapproved to act on behalf of a `delegator`.
    event ManagerApproval(address indexed delegator, address indexed manager, bool isAllowed);

    /// @notice Emitted when a user nonce is incremented.
    /// @param caller The address of the caller.
    /// @param signatory The address of the signatory.
    /// @param usedNonce The used nonce.
    event UserNonceIncremented(address indexed caller, address indexed signatory, uint256 usedNonce);
}
