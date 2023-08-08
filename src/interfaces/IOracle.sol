// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IOracle
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that oracles used by Morpho must implement.
interface IOracle {
    /// @notice Returns the price of the underlying asset.
    function price() external view returns (uint256);
}
