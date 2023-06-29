// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface IBlueBorrowCallback {
    function blueBorrowCallback(int256 collateralDelta, int256 borrowDelta, bytes calldata) external;
}
