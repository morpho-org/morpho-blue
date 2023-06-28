// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

// Market id.
type Id is bytes32;

// Market info.
struct Info {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    uint lLTV;
}

struct Market {
    // User' supply balances.
    mapping(address => uint) supplyShare;
    // User' borrow balances.
    mapping(address => uint) borrowShare;
    // User' collateral balance.
    mapping(address => uint) collateral;
    // Market total supply.
    uint totalSupply;
    // Market total supply shares.
    uint totalSupplyShares;
    // Market total borrow.
    uint totalBorrow;
    // Market total borrow shares.
    uint totalBorrowShares;
    // Interests last update (used to check if a market has been created).
    uint lastUpdate;
}

function irm(uint utilization) pure returns (uint) {
    // Divide by the number of seconds in a year.
    // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
    return utilization / 365 days;
}

contract Blue {
    using MathLib for int;
    using MathLib for uint;
    using SafeTransferLib for IERC20;

    // Storage.

    mapping(Id => Market) private markets;

    // Markets management.

    function createMarket(Info calldata info) external {
        Market storage m = markets[Id.wrap(keccak256(abi.encode(info)))];
        require(m.lastUpdate == 0, "market already exists");

        accrueInterests(m);
    }

    // Suppliers position management.

    /// @dev positive amount to deposit.
    function modifyDeposit(Info calldata info, int amount) external {
        Market storage m = markets[Id.wrap(keccak256(abi.encode(info)))];
        if (amount == 0) return;
        require(m.lastUpdate != 0, "unknown market");

        accrueInterests(m);

        if (m.totalSupply == 0 && amount > 0) {
            m.supplyShare[msg.sender] = 1e18;
            m.totalSupplyShares = 1e18;
        } else {
            int shares = amount.wMul(m.totalSupplyShares).wDiv(m.totalSupply);
            m.supplyShare[msg.sender] = (int(m.supplyShare[msg.sender]) + shares).safeToUint();
            m.totalSupplyShares = (int(m.totalSupplyShares) + shares).safeToUint();
        }

        // No need to check if the integer is positive.
        m.totalSupply = uint(int(m.totalSupply) + amount);

        if (amount < 0) {
            require(m.totalBorrow <= m.totalSupply, "not enough liquidity");
        }

        info.borrowableAsset.handleTransfer({user: msg.sender, amountIn: amount});
    }

    // Borrowers position management.

    /// @dev positive amount to borrow (to discuss).
    function modifyBorrow(Info calldata info, int amount) external {
        Market storage m = markets[Id.wrap(keccak256(abi.encode(info)))];
        if (amount == 0) return;
        require(m.lastUpdate != 0, "unknown market");

        accrueInterests(m);

        if (m.totalBorrow == 0 && amount > 0) {
            m.borrowShare[msg.sender] = 1e18;
            m.totalBorrowShares = 1e18;
        } else {
            int shares = amount.wMul(m.totalBorrowShares).wDiv(m.totalBorrow);
            m.borrowShare[msg.sender] = (int(m.borrowShare[msg.sender]) + shares).safeToUint();
            m.totalBorrowShares = (int(m.totalBorrowShares) + shares).safeToUint();
        }

        // No need to check if the integer is positive.
        m.totalBorrow = uint(int(m.totalBorrow) + amount);

        if (amount > 0) {
            checkHealth(info, msg.sender);
            require(m.totalBorrow <= m.totalSupply, "not enough liquidity");
        }

        info.borrowableAsset.handleTransfer({user: msg.sender, amountIn: -amount});
    }

    /// @dev positive amount to deposit.
    function modifyCollateral(Info calldata info, int amount) external {
        Market storage m = markets[Id.wrap(keccak256(abi.encode(info)))];
        if (amount == 0) return;
        require(m.lastUpdate != 0, "unknown market");

        accrueInterests(m);

        m.collateral[msg.sender] = (int(m.collateral[msg.sender]) + amount).safeToUint();

        if (amount < 0) checkHealth(info, msg.sender);

        info.collateralAsset.handleTransfer({user: msg.sender, amountIn: amount});
    }

    // Interests management.

    function accrueInterests(Market storage m) internal {
        uint bucketTotalSupply = m.totalSupply;

        if (bucketTotalSupply != 0) {
            uint bucketTotalBorrow = m.totalBorrow;
            uint utilization = bucketTotalBorrow.wDiv(bucketTotalSupply);
            uint borrowRate = irm(utilization);
            uint accruedInterests = bucketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - m.lastUpdate);
            m.totalSupply = bucketTotalSupply + accruedInterests;
            m.totalBorrow = bucketTotalBorrow + accruedInterests;
        }

        m.lastUpdate = block.timestamp;
    }

    // Health check.

    function checkHealth(Info calldata info, address user) public view {
        Market storage m = markets[Id.wrap(keccak256(abi.encode(info)))];

        if (m.borrowShare[user] > 0) {
            // totalBorrowShares[bucket] > 0 because borrowShare[user][bucket] > 0.
            uint borrowValue = m.borrowShare[user].wMul(m.totalBorrow).wDiv(m.totalBorrowShares).wMul(
                IOracle(info.borrowableOracle).price()
            );
            uint collateralValue = m.collateral[user].wMul(IOracle(info.collateralOracle).price());
            require(collateralValue.wMul(info.lLTV) >= borrowValue, "not enough collateral");
        }
    }

    // View functions.

    function supplyShare(Id id, address user) external view returns (uint) {
        return markets[id].supplyShare[user];
    }

    function borrowShare(Id id, address user) external view returns (uint) {
        return markets[id].borrowShare[user];
    }

    function collateral(Id id, address user) external view returns (uint) {
        return markets[id].collateral[user];
    }

    function totalSupply(Id id) external view returns (uint) {
        return markets[id].totalSupply;
    }

    function totalSupplyShares(Id id) external view returns (uint) {
        return markets[id].totalSupplyShares;
    }

    function totalBorrow(Id id) external view returns (uint) {
        return markets[id].totalBorrow;
    }

    function totalBorrowShares(Id id) external view returns (uint) {
        return markets[id].totalBorrowShares;
    }

    function lastUpdate(Id id) external view returns (uint) {
        return markets[id].lastUpdate;
    }
}
