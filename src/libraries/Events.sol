// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market} from "src/libraries/MarketLib.sol";

library Events {
    event SuppliedCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount);
    event WithdrawnCollateral(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver, uint256 amount
    );

    event Supplied(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);
    event Withdrawn(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );

    event Borrowed(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );
    event Repaid(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);

    event Liquidated(
        Id indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaid,
        uint256 repaidShares,
        uint256 seized
    );

    event FlashLoan(address indexed caller, address indexed token, address indexed receiver, uint256 amount);

    event OwnerSet(address indexed newOwner);

    event FeeSet(Id indexed id, uint256 fee);

    event FeeRecipientSet(address indexed feeRecipient);

    event MarketCreated(Id indexed id, Market market);

    event BadDebtRealized(Id indexed id, address indexed borrower, uint256 amount, uint256 shares);

    event AuthorizationSet(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized
    );

    event NonceIncremented(address indexed caller, address indexed signatory, uint256 usedNonce);

    event IrmEnabled(address indexed irm);

    event LltvEnabled(uint256 lltv);

    event InterestsAccrued(Id indexed id, uint256 accruedInterests, uint256 feeShares);
}
