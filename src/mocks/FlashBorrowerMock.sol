// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashLender} from "../interfaces/IFlashLender.sol";
import {IFlashBorrower} from "../interfaces/IFlashBorrower.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IFlashBorrower {
    using SafeTransferLib for ERC20;

    IFlashLender private immutable _LENDER;

    constructor(IFlashLender lender) {
        _LENDER = lender;
    }

    /* EXTERNAL */

    /// @inheritdoc IFlashBorrower
    function onBlueFlashLoan(address, address token, uint256 amount, bytes calldata) external {
        require(msg.sender == address(_LENDER), "invalid lender");

        ERC20(token).safeApprove(address(_LENDER), amount);
    }
}
