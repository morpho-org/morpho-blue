// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface VmEnvironment {
    function getBlockTimestamp() external view returns (uint256);
}
