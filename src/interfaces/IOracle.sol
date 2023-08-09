// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IOracle
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that oracles used by Blue must implement.
interface IOracle {
    /// @notice Returns the price of the collateral asset quoted in the borrowable asset and the price's unit scale.
    function price() external view returns (uint256 collateralPrice, uint256 scale);
}
