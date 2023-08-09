// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {Market} from "./IBlue.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Blue must implement.
interface IIrm {
    /// @notice Returns the borrow rate of a `market`.
    function prevBorrowRate(Market memory market) external returns (uint256);
}
