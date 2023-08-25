// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.2;

/// @title IOracle
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that oracles used by Morpho must implement.
interface IOracle {
    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of borrowable token, scaled by 1e36.
    /// @dev It corresponds to the price of 10**(collateral decimals) assets of collateral token quoted in
    /// 10**(borrowable decimals) assets of borrowable token with `36 + borrowable decimals - collateral decimals`
    /// decimals of precision.
    function price() external view returns (uint256);
}
