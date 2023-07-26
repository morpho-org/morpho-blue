// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function blueLiquidateCallback(uint256 seized, uint256 repaid, bytes calldata data) external;
}
