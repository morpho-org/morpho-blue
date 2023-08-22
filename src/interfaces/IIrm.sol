// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {MarketParams} from "./IMorpho.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Morpho must implement.
interface IIrm {
    /// @notice Returns the borrow rate of the market `marketParams`.
    function borrowRate(MarketParams memory marketParams) external returns (uint256);

    /// @notice Returns the borrow rate of the market `marketParams` without modifying the IRM's storage.
    function borrowRateView(MarketParams memory marketParams) external view returns (uint256);
}
