// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "./IMorpho.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Morpho must implement.
interface IIrm {
    /// @notice Returns the borrow rate of a `market`.
    function borrowRate(Market memory market) external view returns (uint256);

    /// @notice Blue calls back through this function to allow the IRM to update its own state.
    function updateIRM(Market memory market) external;
}
