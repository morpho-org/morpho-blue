// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IBlue} from "../interfaces/IBlue.sol";

import {MarketLib} from "./MarketLib.sol";

library BlueLib {
    using MarketLib for Market;

    function withdraw(IBlue blue, Market memory market, uint256 amount, address onBehalf, address receiver)
        external
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toSupplyShares(blue.totalSupply(id), blue.totalSupplyShares(id));

        blue.withdraw(market, shares, onBehalf, receiver, data);
    }

    function repay(IBlue blue, Market memory market, uint256 amount, address onBehalf, bytes calldata data)
        external
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toBorrowShares(blue.totalBorrow(id), blue.totalBorrowShares(id));

        blue.repay(market, shares, onBehalf, data);
    }
}
