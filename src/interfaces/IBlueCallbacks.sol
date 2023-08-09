// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IFlashBlue {
    function onBlueCallback(bytes calldata data) external;
}
