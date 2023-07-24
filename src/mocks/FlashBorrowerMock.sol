// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IFlashLender} from "src/interfaces/IFlashLender.sol";
import {IFlashBorrower, FLASH_BORROWER_SUCCESS_HASH} from "src/interfaces/IFlashBorrower.sol";

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

contract FlashBorrowerMock is IFlashBorrower {
    using SafeTransferLib for IERC20;

    IFlashLender private immutable _LENDER;

    constructor(IFlashLender lender) {
        _LENDER = lender;
    }

    /* EXTERNAL */

    function flashLoan(IERC20 token, uint256 amount, bytes calldata data) external virtual returns (bytes memory) {
        return _LENDER.flashLoan(this, token, amount, data);
    }

    /// @inheritdoc IFlashBorrower
    function onFlashLoan(address initiator, IERC20 token, uint256 amount, bytes calldata)
        external
        virtual
        returns (bytes32, bytes memory)
    {
        require(msg.sender == address(_LENDER), "invalid lender");
        require(initiator == address(this), "invalid initiator");

        token.safeApprove(address(_LENDER), amount);

        return (FLASH_BORROWER_SUCCESS_HASH, bytes(""));
    }
}
