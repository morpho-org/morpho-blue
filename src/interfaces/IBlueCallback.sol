// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueCallback {
    function blueCallback(uint256 amount, bytes calldata data) external;
}
