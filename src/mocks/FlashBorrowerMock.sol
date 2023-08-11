// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashLender} from "../interfaces/IFlashLender.sol";
import {IBlueFlashLoanCallback} from "../interfaces/IBlueCallbacks.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IBlueFlashLoanCallback {
    using SafeTransferLib for ERC20;

    IFlashLender private immutable BLUE;

    constructor(IFlashLender newBlue) {
        BLUE = newBlue;
    }

    function flashLoan(address token, uint256 amount, bytes calldata data) external {
        BLUE.flashLoan(token, amount, data);
    }

    function onBlueFlashLoan(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(BLUE));
        address token = abi.decode(data, (address));
        ERC20(token).safeApprove(address(BLUE), amount);
    }
}
