// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IIrm} from "../../interfaces/IIrm.sol";
import {IFixedRateIrm} from "./interfaces/IFixedRateIrm.sol";

import {MarketParamsLib} from "../../libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../../interfaces/IMorpho.sol";

/* ERRORS */

/// @dev Thrown when the rate is not already set for this market.
string constant RATE_NOT_SET = "rate not set";
/// @dev Thrown when the rate is already set for this market.
string constant RATE_SET = "rate set";
/// @dev Thrown when trying to set the rate at zero.
string constant RATE_ZERO = "rate zero";
/// @dev Thrown when trying to set a rate that is too high.
string constant RATE_TOO_HIGH = "rate too high";

/// @title FixedRateIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
contract FixedRateIrm is IFixedRateIrm {
    using MarketParamsLib for MarketParams;

    /* CONSTANTS */

    /// @inheritdoc IFixedRateIrm
    uint256 public constant MAX_BORROW_RATE = 8.0 ether / uint256(365 days);

    /* STORAGE */

    /// @inheritdoc IFixedRateIrm
    mapping(Id => uint256) public borrowRateStored;

    /* SETTER */

    /// @inheritdoc IFixedRateIrm
    function setBorrowRate(Id id, uint256 newBorrowRate) external {
        require(borrowRateStored[id] == 0, RATE_SET);
        require(newBorrowRate != 0, RATE_ZERO);
        require(newBorrowRate <= MAX_BORROW_RATE, RATE_TOO_HIGH);

        borrowRateStored[id] = newBorrowRate;

        emit SetBorrowRate(id, newBorrowRate);
    }

    /* BORROW RATES */

    /// @inheritdoc IIrm
    function borrowRateView(MarketParams memory marketParams, Market memory) external view returns (uint256) {
        uint256 borrowRateCached = borrowRateStored[marketParams.id()];
        require(borrowRateCached != 0, RATE_NOT_SET);
        return borrowRateCached;
    }

    /// @inheritdoc IIrm
    /// @dev Reverts on not set rate, so the rate has to be set before the market creation.
    function borrowRate(MarketParams memory marketParams, Market memory) external view returns (uint256) {
        uint256 borrowRateCached = borrowRateStored[marketParams.id()];
        require(borrowRateCached != 0, RATE_NOT_SET);
        return borrowRateCached;
    }
}
