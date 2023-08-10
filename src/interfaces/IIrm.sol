// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {MarketParams} from "./IBlue.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Blue must implement.
interface IIrm {
    /// @notice Returns the borrow rate of a `marketParams`.
    function borrowRate(MarketParams memory marketParams) external returns (uint256);
}
