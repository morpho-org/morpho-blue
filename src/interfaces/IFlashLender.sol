// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IBlueFlashLoanCallback} from "./IBlueCallbacks.sol";

interface IFlashLender {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}
