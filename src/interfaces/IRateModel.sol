// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRateModel {
    function dBorrowRate(uint256 utilization) external view returns (uint256);
}
