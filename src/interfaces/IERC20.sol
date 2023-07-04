// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IERC20 {
    function transferFrom(address, address, uint) external;
    function transfer(address, uint) external;
}
