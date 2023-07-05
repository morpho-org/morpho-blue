// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @dev Empty because we only call functions in assembly. It prevents calling
/// transfer (transferFrom) instead of safeTransfer (safeTransferFrom).
interface IERC20 {}
