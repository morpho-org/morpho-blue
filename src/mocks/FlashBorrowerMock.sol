// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashLender} from "../interfaces/IFlashLender.sol";
import {IMorphoFlashLoanCallback} from "../interfaces/IMorphoCallbacks.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IMorphoFlashLoanCallback {
    using SafeTransferLib for ERC20;

    IFlashLender private immutable BLUE;

    constructor(IFlashLender newMorpho) {
        BLUE = newMorpho;
    }

    function flashLoan(address token, uint256 amount, bytes calldata data) external {
        BLUE.flashLoan(token, amount, data);
    }

    function onMorphoFlashLoan(address token, uint256 amount, bytes calldata) external {
        require(msg.sender == address(BLUE));
        ERC20(token).safeApprove(address(BLUE), amount);
    }
}
