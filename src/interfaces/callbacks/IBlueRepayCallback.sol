// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueRepayCallback {
    function blueRepayCallback(uint256 amountToRepay, bytes calldata data) external;
}
