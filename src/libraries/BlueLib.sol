// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IBlue} from "../interfaces/IBlue.sol";

import {MarketLib} from "./MarketLib.sol";
import {SharesMath} from "./SharesMath.sol";

library BlueLib {
    using MarketLib for Market;
    using SharesMath for uint256;

    function computeWithdrawShares(IBlue blue, Market memory market, uint256 amount)
        internal
        view
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toWithdrawShares(blue.totalSupply(id), blue.totalSupplyShares(id));

        uint256 maxShares = blue.supplyShares(id, address(this));
        if (shares > maxShares) shares = maxShares;
    }

    function computeRepayShares(IBlue blue, Market memory market, uint256 amount)
        internal
        view
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toRepayShares(blue.totalBorrow(id), blue.totalBorrowShares(id));

        uint256 maxShares = blue.borrowShares(id, address(this));
        if (shares > maxShares) shares = maxShares;
    }
}
