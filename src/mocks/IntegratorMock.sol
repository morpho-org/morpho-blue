// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Blue} from "src/Blue.sol";

import {Market, MarketLib} from "src/libraries/MarketLib.sol";
import {SafeTransferLib, IERC20} from "src/libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

contract IntegratorMock {
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    Blue internal immutable _BLUE;

    constructor(Blue blue) {
        _BLUE = blue;
    }

    /// @dev Withdraws `amount` of `asset` on behalf of `onBehalf`. Sender must have previously approved the bulker as their manager on Morpho.
    function withdrawAll(Market memory market, address receiver) external {
        uint256 withdrawn = _BLUE.withdraw(market, type(uint256).max, msg.sender, address(this));

        _supplySomewhereElse(withdrawn / 2);

        if (receiver != address(this)) market.borrowableAsset.safeTransfer(receiver, withdrawn / 2);
    }

    function _supplySomewhereElse(uint256 amount) internal {}
}
