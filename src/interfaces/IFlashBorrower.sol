// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @dev Interface of the FlashBorrower, inspired by https://eips.ethereum.org/EIPS/eip-3156.
///      The FlashLender's `flashLoan` function now returns the FlashBorrower's return data.
interface IFlashBorrower {
    /// @dev Receive a flash loan.
    /// @param initiator The initiator of the loan.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    /// @return The keccak256 hash of "FlashBorrower.onFlashLoan" and any additional arbitrary data.
    function onFlashLoan(address initiator, IERC20 token, uint256 amount, bytes calldata data)
        external
        returns (bytes32, bytes memory);
}
