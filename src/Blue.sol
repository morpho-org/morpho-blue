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

    function createMarket(Info calldata info) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
        require(lastUpdate[id] == 0, "market already exists");

        accrueInterests(id);
    }

    // Supply management.

    function supply(Info calldata info, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        if (totalSupply[id] == 0 && amount > 0) {
            supplyShare[id][msg.sender] = 1e18;
            totalSupplyShares[id] = 1e18;
        } else {
            uint shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
            supplyShare[id][msg.sender] += supplyShare[id][msg.sender] + shares;
            totalSupplyShares[id] += shares;
        }

        totalSupply[id] += amount;

        info.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Info calldata info, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        uint shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
        supplyShare[id][msg.sender] -= shares;
        totalSupplyShares[id] -= shares;
        
        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        info.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Info calldata info, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
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

        checkHealth(info, id, msg.sender);
        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        info.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Info calldata info, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        uint shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
        borrowShare[id][msg.sender] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        info.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    function supplyCollateral(Info calldata info, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        collateral[id][msg.sender] += amount;

        info.collateralAsset.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Info calldata info, uint amount) external {
        Id id = Id.wrap(keccak256(abi.encode(info)));
        require(lastUpdate[id] != 0, "unknown market");
        require(amount > 0, "zero amount");

        accrueInterests(id);

        collateral[id][msg.sender] -= amount;

        checkHealth(info, id, msg.sender);

        info.collateralAsset.transfer(msg.sender, amount);
    }

    // Interests management.

    function accrueInterests(Id id) internal {
        uint bucketTotalSupply = totalSupply[id];

        if (bucketTotalSupply != 0) {
            uint bucketTotalBorrow = totalBorrow[id];
            uint utilization = bucketTotalBorrow.wDiv(bucketTotalSupply);
            uint borrowRate = irm(utilization);
            uint accruedInterests = bucketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - lastUpdate[id]);
            totalSupply[id] = bucketTotalSupply + accruedInterests;
            totalBorrow[id] = bucketTotalBorrow + accruedInterests;
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function checkHealth(Info calldata info, Id id, address user) public view {
        if (borrowShare[id][user] > 0) {
            // totalBorrowShares[bucket] > 0 because borrowShare[user][bucket] > 0.
            uint borrowValue = borrowShare[id][user].wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]).wMul(
                IOracle(info.borrowableOracle).price()
            );
            uint collateralValue = collateral[id][user].wMul(IOracle(info.collateralOracle).price());
            require(collateralValue.wMul(info.lLTV) >= borrowValue, "not enough collateral");
        }
    }
}
