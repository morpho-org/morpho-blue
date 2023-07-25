// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC3156FlashLender} from "src/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower, FLASH_BORROWER_SUCCESS_HASH} from "src/interfaces/IERC3156FlashBorrower.sol";

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

contract FlashBorrowerMock is IERC3156FlashBorrower {
    using SafeTransferLib for IERC20;

    IERC3156FlashLender private immutable _LENDER;

    constructor(IERC3156FlashLender lender) {
        _LENDER = lender;
    }

    /* EXTERNAL */

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        require(msg.sender == address(_LENDER), "invalid lender");

        IERC20(token).safeApprove(address(_LENDER), amount + fee);

        return FLASH_BORROWER_SUCCESS_HASH;
    }
}
