// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MarketParams, Id, IBlue} from "../interfaces/IBlue.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

struct Market {
    mapping(address => UserBalances) userBalances;
    MarketState marketState;
}

struct UserBalances {
    uint128 borrowShares; // User' borrow balances.
    uint128 collateral; // User' collateral balance.
    uint128 supplyShares; // User' supply balances.
}

struct MarketState {
    uint128 totalSupply; // Market total supply.
    uint128 totalSupplyShares; // Market total supply shares.
    uint128 totalBorrow; // Market total borrow.
    uint128 totalBorrowShares; // Market total borrow shares.
    uint64 lastUpdate; // Interests last update (used to check if a market has been created).
    uint8 fee; // Fee.
}

/// @title MarketLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to convert a market to its id.
library MarketLib {
    using SafeCastLib for uint256;

    function id(MarketParams memory marketParams) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams)));
    }

    function supplyShares(Market storage market, address user) internal view returns (uint256) {
        return uint256(market.userBalances[user].supplyShares);
    }

    function borrowShares(Market storage market, address user) internal view returns (uint256) {
        return uint256(market.userBalances[user].borrowShares);
    }

    function collateral(Market storage market, address user) internal view returns (uint256) {
        return uint256(market.userBalances[user].collateral);
    }

    function totalSupply(Market storage market) internal view returns (uint256) {
        return uint256(market.marketState.totalSupply);
    }

    function totalSupplyShares(Market storage market) internal view returns (uint256) {
        return uint256(market.marketState.totalSupplyShares);
    }

    function totalBorrow(Market storage market) internal view returns (uint256) {
        return uint256(market.marketState.totalBorrow);
    }

    function totalBorrowShares(Market storage market) internal view returns (uint256) {
        return uint256(market.marketState.totalBorrowShares);
    }

    function lastUpdate(Market storage market) internal view returns (uint256) {
        return uint256(market.marketState.lastUpdate);
    }

    function fee(Market storage market) internal view returns (uint256) {
        return uint256(market.marketState.fee);
    }

    function setSupplyShares(Market storage market, address user, uint256 amount) internal {
        market.userBalances[user].supplyShares = amount.safeCastTo128();
    }

    function setBorrowShares(Market storage market, address user, uint256 amount) internal {
        market.userBalances[user].borrowShares = amount.safeCastTo128();
    }

    function setCollateral(Market storage market, address user, uint256 amount) internal {
        market.userBalances[user].collateral = amount.safeCastTo128();
    }

    function setTotalSupply(Market storage market, uint256 amount) internal {
        market.marketState.totalSupply = amount.safeCastTo128();
    }

    function setTotalSupplyShares(Market storage market, uint256 amount) internal {
        market.marketState.totalSupplyShares = amount.safeCastTo128();
    }

    function setTotalBorrow(Market storage market, uint256 amount) internal {
        market.marketState.totalBorrow = amount.safeCastTo128();
    }

    function setTotalBorrowShares(Market storage market, uint256 amount) internal {
        market.marketState.totalBorrowShares = amount.safeCastTo128();
    }

    function setLastUpdate(Market storage market, uint256 amount) internal {
        market.marketState.lastUpdate = amount.safeCastTo64();
    }

    function setFee(Market storage market, uint256 amount) internal {
        market.marketState.fee = amount.safeCastTo8();
    }
}
