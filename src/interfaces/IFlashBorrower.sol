// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IFlashBorrower {
    /// @dev Receives a flash loan.
    /// @param initiator The initiator of the loan.
    /// @param token The token lent.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    function onFlashLoan(address initiator, address token, uint256 amount, bytes calldata data) external;
}
