// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function blueLiquidateCallback(uint256 amountSeized, uint256 amountToRepay, bytes calldata data) external;
}
