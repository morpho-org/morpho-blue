// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../interfaces/IMorpho.sol";

import {MarketLib} from "./MarketLib.sol";
import {SharesMath} from "./SharesMath.sol";

/// @title MorphoLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice A library to ease interactions with Morpho.
library MorphoLib {
    using MarketLib for Market;
    using SharesMath for uint256;

    function withdrawAmount(IMorpho morpho, Market memory market, uint256 amount, address onBehalf, address receiver)
        internal
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toWithdrawShares(morpho.totalSupply(id), morpho.totalSupplyShares(id));

        uint256 maxShares = morpho.supplyShares(id, address(this));
        if (shares > maxShares) shares = maxShares;

        morpho.withdraw(market, shares, onBehalf, receiver);
    }

    function repayAmount(IMorpho morpho, Market memory market, uint256 amount, address onBehalf, bytes memory data)
        internal
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toRepayShares(morpho.totalBorrow(id), morpho.totalBorrowShares(id));

        uint256 maxShares = morpho.borrowShares(id, address(this));
        if (shares > maxShares) shares = maxShares;

        morpho.repay(market, shares, onBehalf, data);
    }
}
