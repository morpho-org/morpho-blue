// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market} from "src/libraries/MarketLib.sol";

library Events {
    event SupplyCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets);
    event WithdrawCollateral(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver, uint256 assets
    );

    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    event Borrow(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);

    event Liquidate(
        Id indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaid,
        uint256 repaidShares,
        uint256 seized,
        uint256 badDebtShares
    );

    event FlashLoan(address indexed caller, address indexed token, uint256 assets);

    event SetOwner(address indexed newOwner);

    event SetFee(Id indexed id, uint256 fee);

    event SetFeeRecipient(address indexed feeRecipient);

    event CreateMarket(Id indexed id, Market market);

    event SetAuthorization(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized
    );

    event IncrementNonce(address indexed caller, address indexed signatory, uint256 usedNonce);

    event EnableIrm(address indexed irm);

    event EnableLltv(uint256 lltv);

    event AccrueInterests(Id indexed id, uint256 borrowRate, uint256 accruedInterests, uint256 feeShares);
}
