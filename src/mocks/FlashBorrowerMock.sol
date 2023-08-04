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

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        BLUE.flashLoan(token, assets, data);
    }

    function onBlueFlashLoan(address token, uint256 assets, bytes calldata) external {
        require(msg.sender == address(BLUE));
        ERC20(token).safeApprove(address(BLUE), assets);
    }
}
