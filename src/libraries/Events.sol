// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Market} from "src/libraries/MarketLib.sol";

library Events {
    event CollateralSupply(bytes32 indexed id, address indexed caller, address indexed onBehalf, uint256 amount);
    event CollateralWithdraw(bytes32 indexed id, address caller, address indexed onBehalf, uint256 amount);

    event Supply(bytes32 indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);
    event Withdraw(
        bytes32 indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares
    );

    event Borrow(bytes32 indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);
    event Repay(bytes32 indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);

    event Liquidation(
        bytes32 indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaid,
        uint256 repaidShares,
        uint256 seized
    );

    event Flashloan(address indexed caller, address indexed token, address indexed receiver, uint256 amount);

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    event FeeSet(bytes32 indexed id, uint256 fee);

    event FeeRecipientSet(address indexed feeRecipient);

    event MarketCreated(Market market);

    event BadDebtRealized(bytes32 indexed id, address indexed borrower, uint256 amount, uint256 shares);

    event Approval(address indexed caller, address indexed delegator, address indexed manager, bool isApproved);

    event NonceIncremented(address indexed caller, address indexed signatory, uint256 usedNonce);

    event IrmEnabled(address indexed irm);

    event LltvEnabled(uint256 lltv);

    event InterestsAccrued(bytes32 indexed id, uint256 accruedInterests);
}
