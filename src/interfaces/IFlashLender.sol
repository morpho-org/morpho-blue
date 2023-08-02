// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IBlueFlashLoanCallback} from "./IBlueCallbacks.sol";

interface IFlashLender {
    function flashLoan(address token, uint256 amount, bytes calldata data) external;
}
