// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IOracle {
    function price() external view returns (uint256 wad, bool canBorrow, bool canWithdrawCollateral);
}
