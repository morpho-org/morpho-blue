// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IFlashBorrower} from "./IFlashBorrower.sol";

/// @dev Interface of the Flash Lender, inspired by https://eips.ethereum.org/EIPS/eip-3156.
///      The FlashLender's `flashLoan` function now returns the FlashBorrower's return data.
interface IFlashLender {
    /// @dev Initiate a flash loan.
    /// @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    function flashLoan(IFlashBorrower receiver, IERC20 token, uint256 amount, bytes calldata data)
        external
        returns (bytes memory);
}
