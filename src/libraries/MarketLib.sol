// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MarketParams, Id} from "../interfaces/IMorpho.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

struct Market {
    mapping(address => UserBalances) userBalances;
    uint128 totalSupply; // Market total supply.
    uint128 totalSupplyShares; // Market total supply shares.
    uint128 totalBorrow; // Market total borrow.
    uint128 totalBorrowShares; // Market total borrow shares.
    uint128 lastUpdate; // Interests last update (used to check if a market has been created).
    uint128 fee; // Fee.
}

struct UserBalances {
    uint128 borrowShares; // User' borrow balances.
    uint128 collateral; // User' collateral balance.
    uint128 supplyShares; // User' supply balances.
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
        return market.userBalances[user].supplyShares;
    }

    function borrowShares(Market storage market, address user) internal view returns (uint256) {
        return market.userBalances[user].borrowShares;
    }

    function collateral(Market storage market, address user) internal view returns (uint256) {
        return market.userBalances[user].collateral;
    }

    function setSupplyShares(Market storage market, address user, uint256 amount) internal {
        market.userBalances[user].supplyShares = amount.safeCastTo128();
    }

    function increaseSupplyShares(Market storage market, address user, uint256 amount) internal {
        setSupplyShares(market, user, supplyShares(market, user) + amount);
    }

    function decreaseSupplyShares(Market storage market, address user, uint256 amount) internal {
        setSupplyShares(market, user, supplyShares(market, user) - amount);
    }

    function setBorrowShares(Market storage market, address user, uint256 amount) internal {
        market.userBalances[user].borrowShares = amount.safeCastTo128();
    }

    function increaseBorrowShares(Market storage market, address user, uint256 amount) internal {
        setBorrowShares(market, user, borrowShares(market, user) + amount);
    }

    function decreaseBorrowShares(Market storage market, address user, uint256 amount) internal {
        setBorrowShares(market, user, borrowShares(market, user) - amount);
    }

    function setCollateral(Market storage market, address user, uint256 amount) internal {
        market.userBalances[user].collateral = amount.safeCastTo128();
    }

    function increaseCollateral(Market storage market, address user, uint256 amount) internal {
        setCollateral(market, user, collateral(market, user) + amount);
    }

    function decreaseCollateral(Market storage market, address user, uint256 amount) internal {
        setCollateral(market, user, collateral(market, user) - amount);
    }

    function setTotalSupply(Market storage market, uint256 amount) internal {
        market.totalSupply = amount.safeCastTo128();
    }

    function increaseTotalSupply(Market storage market, uint256 amount) internal {
        setTotalSupply(market, market.totalSupply + amount);
    }

    function decreaseTotalSupply(Market storage market, uint256 amount) internal {
        setTotalSupply(market, market.totalSupply - amount);
    }

    function setTotalSupplyShares(Market storage market, uint256 amount) internal {
        market.totalSupplyShares = amount.safeCastTo128();
    }

    function increaseTotalSupplyShares(Market storage market, uint256 amount) internal {
        setTotalSupplyShares(market, market.totalSupplyShares + amount);
    }

    function decreaseTotalSupplyShares(Market storage market, uint256 amount) internal {
        setTotalSupplyShares(market, market.totalSupplyShares - amount);
    }

    function setTotalBorrow(Market storage market, uint256 amount) internal {
        market.totalBorrow = amount.safeCastTo128();
    }

    function increaseTotalBorrow(Market storage market, uint256 amount) internal {
        setTotalBorrow(market, market.totalBorrow + amount);
    }

    function decreaseTotalBorrow(Market storage market, uint256 amount) internal {
        setTotalBorrow(market, market.totalBorrow - amount);
    }

    function setTotalBorrowShares(Market storage market, uint256 amount) internal {
        market.totalBorrowShares = amount.safeCastTo128();
    }

    function increaseTotalBorrowShares(Market storage market, uint256 amount) internal {
        setTotalBorrowShares(market, market.totalBorrowShares + amount);
    }

    function decreaseTotalBorrowShares(Market storage market, uint256 amount) internal {
        setTotalBorrowShares(market, market.totalBorrowShares - amount);
    }

    function setLastUpdate(Market storage market, uint256 amount) internal {
        market.lastUpdate = amount.safeCastTo128();
    }

    function setFee(Market storage market, uint256 amount) internal {
        market.fee = amount.safeCastTo128();
    }
}
