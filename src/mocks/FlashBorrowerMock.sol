// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBlueFlashloanCallback} from "../interfaces/IBlueCallbacks.sol";
import {Blue} from "../Blue.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IBlueFlashloanCallback {
    using SafeTransferLib for ERC20;

    Blue private immutable blue;

    constructor(Blue newBlue) {
        blue = newBlue;
    }

    function flashLoan(address token, uint256 amount, bytes calldata data) external {
        blue.flashLoan(token, amount, data);
    }

    function onBlueFlashLoan(address token, uint256 amount, bytes calldata) external {
        require(msg.sender == address(blue));
        ERC20(token).safeApprove(address(blue), amount);
    }
}
