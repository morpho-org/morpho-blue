// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

// Market id.
type Id is bytes32;

// Market.
struct Market {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    uint lLTV;
}

function irm(uint utilization) pure returns (uint) {
    // Divide by the number of seconds in a year.
    // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
    return utilization / 365 days;
}

contract Blue {
    using MathLib for uint;
    using SafeTransferLib for IERC20;

    // Storage.

    // User' supply balances.
    mapping(Id => mapping(address => uint)) public supplyShare;
    // User' borrow balances.
    mapping(Id => mapping(address => uint)) public borrowShare;
    // User' collateral balance.
    mapping(Id => mapping(address => uint)) public collateral;
    // Market total supply.
    mapping(Id => uint) public totalSupply;
    // Market total supply shares.
    mapping(Id => uint) public totalSupplyShares;
    // Market total borrow.
    mapping(Id => uint) public totalBorrow;
    // Market total borrow shares.
    mapping(Id => uint) public totalBorrowShares;
    // Interests last update (used to check if a market has been created).
    mapping(Id => uint) public lastUpdate;

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] == 0, "market already exists");

        accrueInterests(id);
    }

    // Supply management.

    function supply(Market calldata market, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        if (totalSupply[id] == 0) {
            supplyShare[id][msg.sender] = 1e18;
            totalSupplyShares[id] = 1e18;
        } else {
            uint shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
            supplyShare[id][msg.sender] += shares;
            totalSupplyShares[id] += shares;
        }

        totalSupply[id] += amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        uint shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
        supplyShare[id][msg.sender] -= shares;
        totalSupplyShares[id] -= shares;

        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        if (totalBorrow[id] == 0) {
            borrowShare[id][msg.sender] = 1e18;
            totalBorrowShares[id] = 1e18;
        } else {
            uint shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
            borrowShare[id][msg.sender] += shares;
            totalBorrowShares[id] += shares;
        }

        totalBorrow[id] += amount;

        checkHealth(market, id, msg.sender);
        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        uint shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
        borrowShare[id][msg.sender] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    function supplyCollateral(Market calldata market, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        collateral[id][msg.sender] += amount;

        market.collateralAsset.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        collateral[id][msg.sender] -= amount;

        checkHealth(market, id, msg.sender);

        market.collateralAsset.transfer(msg.sender, amount);
    }

    // Interests management.

    function accrueInterests(Id id) private {
        uint marketTotalSupply = totalSupply[id];

        if (marketTotalSupply != 0) {
            uint marketTotalBorrow = totalBorrow[id];
            uint utilization = marketTotalBorrow.wDiv(marketTotalSupply);
            uint borrowRate = irm(utilization);
            uint accruedInterests = marketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - lastUpdate[id]);
            totalSupply[id] = marketTotalSupply + accruedInterests;
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function checkHealth(Market calldata market, Id id, address user) private view {
        if (borrowShare[id][user] > 0) {
            // totalBorrowShares[id] > 0 because borrowShare[id][user] > 0.
            uint borrowValue = borrowShare[id][user].wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]).wMul(
                IOracle(market.borrowableOracle).price()
            );
            uint collateralValue = collateral[id][user].wMul(IOracle(market.collateralOracle).price());
            require(collateralValue.wMul(market.lLTV) >= borrowValue, "not enough collateral");
        }
    }
}
