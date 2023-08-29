// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.2;

import {MarketParams, Market} from "./IMorpho.sol";

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface that IRMs used by Morpho must implement.
interface IIrm {
    /// @notice Returns the borrow rate of the market `marketParams`.
    /// @param marketParams The MarketParams struct of the market.
    /// @param market The Market struct of the market.
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256);

    /// @notice Returns the borrow rate of the market `marketParams` without modifying any storage.
    /// @param marketParams The MarketParams struct of the market.
    /// @param market The Market struct of the market.
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256);
}
