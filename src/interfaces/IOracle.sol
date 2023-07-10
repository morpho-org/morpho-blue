// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IOracle {
    function price() external view returns (uint256);
}
