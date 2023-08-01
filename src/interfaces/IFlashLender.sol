// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IFlashBorrower} from "./IFlashBorrower.sol";

interface IFlashLender {
    /// @dev Initiate a flash loan.
    /// @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
    /// @param token The token lent.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    function flashLoan(IFlashBorrower receiver, address token, uint256 amount, bytes calldata data) external;
}
