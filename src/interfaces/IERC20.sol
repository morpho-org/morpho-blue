// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IERC20
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing errors used in Blue.
/// @dev Empty because we only call functions in assembly. It prevents calling transfer (transferFrom) instead of safeTransfer (safeTransferFrom).
interface IERC20 {}
