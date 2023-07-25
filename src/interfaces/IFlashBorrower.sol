// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @dev The expected success hash returned by the FlashBorrower.
bytes32 constant FLASH_BORROWER_SUCCESS_HASH = keccak256("FlashBorrower.onFlashLoan");

/// @dev Interface of the FlashBorrower, inspired by https://eips.ethereum.org/EIPS/eip-3156.
///      The FlashLender's `flashLoan` function now returns the FlashBorrower's return data.
interface IFlashBorrower {
    /// @dev Receives a flash loan.
    /// @param initiator The initiator of the loan.
    /// @param token The token lent.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data, intended to contain user-defined parameters.
    /// @return The keccak256 hash of "FlashBorrower.onFlashLoan" and any additional arbitrary data.
    function onFlashLoan(address initiator, IERC20 token, uint256 amount, bytes calldata data)
        external
        returns (bytes32, bytes memory);
}
