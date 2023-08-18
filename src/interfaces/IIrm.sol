// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Config} from "./IMorpho.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Morpho must implement.
interface IIrm {
    /// @notice Returns the borrow rate of a `market`.
    function borrowRate(Config memory config) external returns (uint256);

    /// @notice Returns the borrow rate of a `market` without modifying the IRM's storage.
    function borrowRateView(Config memory config) external view returns (uint256);
}
