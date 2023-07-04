// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MarketKey} from "../libraries/Types.sol";

/// @dev Interface of the ERC3156x FlashBorrower, inspired by https://eips.ethereum.org/EIPS/eip-3156, modified for specific liquidation purposes.
interface IERC3156xFlashLiquidator {
    /* FUNCTIONS */

    /// @dev Receives collateral seized before being asked the debt repaid.
    /// @param initiator The initiator of the loan.
    /// @param marketKey The market configuration.
    /// @param user The user being liquidated.
    /// @param repaid The amount of debt to repay.
    /// @param seized The amount of collateral received.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    /// @return The keccak256 hash of "IERC3156xFlashLiquidator.onLiquidation" and any additional arbitrary data.
    function onLiquidation(
        address initiator,
        MarketKey calldata marketKey,
        address user,
        uint256 repaid,
        uint256 seized,
        bytes calldata data
    ) external returns (bytes32, bytes memory);
}
