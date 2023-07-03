// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

library Events {
    event CollateralDeposit(bytes32 indexed marketId, address indexed caller, address indexed onBehalf, uint256 assets);
    event CollateralWithdraw(
        bytes32 indexed marketId, address caller, address indexed onBehalf, address indexed receiver, uint256 assets
    );

    event Deposit(
        bytes32 indexed marketId, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares
    );
    event Withdraw(
        bytes32 indexed marketId,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    event Borrow(
        bytes32 indexed marketId,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event Repay(
        bytes32 indexed marketId, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares
    );

    event Liquidation(
        bytes32 indexed marketId,
        address indexed caller,
        address indexed borrower,
        address liquidator,
        address receiver,
        uint256 repaid,
        uint256 seized
    );

    event Approval(address indexed delegator, address indexed manager, uint256 allowance);

    event IsWhitelistedSet(address indexed target, bool isWhitelisted);
}
