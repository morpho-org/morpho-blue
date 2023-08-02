// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBlueFlashLoanCallback} from "../interfaces/IBlueCallbacks.sol";
import {Blue} from "../Blue.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IBlueFlashLoanCallback {
    using SafeTransferLib for ERC20;

    Blue private immutable BLUE;

    constructor(Blue newBlue) {
        BLUE = newBlue;
    }

    function flashLoan(address token, uint256 amount, bytes calldata data) external {
        BLUE.flashLoan(token, amount, data);
    }

    function onBlueFlashLoan(address token, uint256 amount, bytes calldata) external {
        require(msg.sender == address(BLUE));
        ERC20(token).safeApprove(address(BLUE), amount);
    }
}
