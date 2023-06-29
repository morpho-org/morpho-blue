// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface IBlueBorrowCallback {
    function blueBorrowCallback(bytes calldata) external;
}
