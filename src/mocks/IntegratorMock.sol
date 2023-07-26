// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Blue} from "src/Blue.sol";

import {Id, Market, MarketLib} from "src/libraries/MarketLib.sol";
import {SafeTransferLib, IERC20} from "src/libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

contract IntegratorMock {
    using MarketLib for Market;
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    Blue internal immutable _BLUE;

    constructor(Blue blue) {
        _BLUE = blue;
    }

    /// @dev Withdraws `amount` of `asset` on behalf of `onBehalf`. Sender must have previously approved the bulker as their manager on Morpho.
    function withdrawAll(Market memory market, address receiver) external {
        Id id = market.id();

        _BLUE.accrueInterests(market, id);

        uint256 shares = _BLUE.supplyShare(id, msg.sender);
        uint256 totalSupply = _BLUE.totalSupply(id);
        uint256 totalSupplyShares = _BLUE.totalSupplyShares(id);

        uint256 amount = shares.mulDivDown(totalSupply, totalSupplyShares);

        _BLUE.withdraw(market, amount, msg.sender);

        if (receiver != address(this)) market.borrowableAsset.safeTransfer(receiver, amount);
    }
}
