// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @dev The expected success hash returned by the FlashBorrower.
bytes32 constant FLASH_BORROWER_SUCCESS_HASH = keccak256("ERC3156FlashBorrower.onFlashLoan");

interface IERC3156FlashBorrower {
    /**
     * @dev Receives a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The token lent.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32);
}
