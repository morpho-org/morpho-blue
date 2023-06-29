// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface IBlueLiquidateCallback {
    function blueLiquidateCallback(uint256 repaid, uint256 seized, bytes calldata) external;
}
