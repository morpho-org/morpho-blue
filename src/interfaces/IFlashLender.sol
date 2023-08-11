// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IFlashLender
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Flash lender interface exposing a flash loan function.
interface IFlashLender {
    /// @notice Executes a flash loan.
    /// @param token The token to flash loan.
    /// @param assets The assets to flash loan.
    /// @param data Arbitrary data to pass to the `onBlueFlashLoan` callback.
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}
