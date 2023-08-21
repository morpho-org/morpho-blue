// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {MarketParams, Market} from "./IMorpho.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Morpho must implement.
interface IIrm {
    /// @notice .
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256);

    /// @notice .
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256);
}
