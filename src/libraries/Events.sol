// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market} from "src/libraries/MarketLib.sol";

library Events {
    event CollateralSupply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount);
    event CollateralWithdraw(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver, uint256 amount
    );

    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);
    event Withdraw(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );

    event Borrow(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);

    event Liquidation(
        Id indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaid,
        uint256 repaidShares,
        uint256 seized
    );

    event Flashloan(address indexed caller, address indexed token, address indexed receiver, uint256 amount);

    event OwnerSet(address indexed newOwner);

    event FeeSet(Id indexed id, uint256 fee);

    event FeeRecipientSet(address indexed feeRecipient);

    event MarketCreated(Market market);

    event BadDebtRealized(Id indexed id, address indexed borrower, uint256 amount, uint256 shares);

    event Authorization(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized
    );

    event NonceIncremented(address indexed caller, address indexed signatory, uint256 usedNonce);

    event IrmEnabled(address indexed irm);

    event LltvEnabled(uint256 lltv);

    event InterestsAccrued(Id indexed id, uint256 accruedInterests);
}
