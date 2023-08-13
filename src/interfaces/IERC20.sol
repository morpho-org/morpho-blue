// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IERC20
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
interface IERC20 {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
