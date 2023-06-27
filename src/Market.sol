// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint constant N = 10;

function bucketToLLTV(uint bucket) pure returns (uint) {
    return MathLib.wDiv(bucket, N - 1);
}

function irm(uint utilization) pure returns (uint) {
    // Divide by the number of seconds in a year.
    // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
    return utilization / 365 days;
}

contract Market {
    using MathLib for int;
    using MathLib for uint;
    using SafeTransferLib for IERC20;

    // Constants.

    uint public constant getN = N;

    address public immutable borrowableAsset;
    address public immutable collateralAsset;
    address public immutable borrowableOracle;
    address public immutable collateralOracle;

    // Storage.

    // User' supply balances.
    mapping(address => mapping(uint => uint)) public supplyShare;
    // User' borrow balances.
    mapping(address => mapping(uint => uint)) public borrowShare;
    // User' collateral balance.
    mapping(address => mapping(uint => uint)) public collateral;
    // Market total supply.
    mapping(uint => uint) public totalSupply;
    // Market total supply shares.
    mapping(uint => uint) public totalSupplyShares;
    // Market total borrow.
    mapping(uint => uint) public totalBorrow;
    // Market total borrow shares.
    mapping(uint => uint) public totalBorrowShares;
    // Interests last update.
    mapping(uint => uint) public lastUpdate;

    // Constructor.

    constructor(
        address newBorrowableAsset,
        address newCollateralAsset,
        address newBorrowableOracle,
        address newCollateralOracle
    ) {
        borrowableAsset = newBorrowableAsset;
        collateralAsset = newCollateralAsset;
        borrowableOracle = newBorrowableOracle;
        collateralOracle = newCollateralOracle;
    }

    // Suppliers position management.

    /// @dev positive amount to deposit.
    function modifyDeposit(int amount, uint bucket) external {
        if (amount == 0) return;
        require(bucket < N, "unknown bucket");

        accrueInterests(bucket);

        if (totalSupply[bucket] == 0) {
            supplyShare[msg.sender][bucket] = 1e18;
            totalSupplyShares[bucket] = 1e18;
        } else {
            int shares = amount.wMul(totalSupplyShares[bucket]).wDiv(totalSupply[bucket]);
            supplyShare[msg.sender][bucket] = (int(supplyShare[msg.sender][bucket]) + shares).safeToUint();
            totalSupplyShares[bucket] = (int(totalSupplyShares[bucket]) + shares).safeToUint();
        }

        // No need to check if the integer is positive.
        totalSupply[bucket] = uint(int(totalSupply[bucket]) + amount);

        if (amount < 0) require(totalBorrow[bucket] <= totalSupply[bucket], "not enough liquidity");

        IERC20(borrowableAsset).handleTransfer({user: msg.sender, amountIn: amount});
    }

    // Borrowers position management.

    /// @dev positive amount to borrow (to discuss).
    function modifyBorrow(int amount, uint bucket) external {
        if (amount == 0) return;
        require(bucket < N, "unknown bucket");

        accrueInterests(bucket);

        if (totalBorrow[bucket] == 0) {
            borrowShare[msg.sender][bucket] = 1e18;
            totalBorrowShares[bucket] = 1e18;
        } else {
            int shares = amount.wMul(totalBorrowShares[bucket]).wDiv(totalBorrow[bucket]);
            borrowShare[msg.sender][bucket] = (int(borrowShare[msg.sender][bucket]) + shares).safeToUint();
            totalBorrowShares[bucket] = (int(totalBorrowShares[bucket]) + shares).safeToUint();
        }

        // No need to check if the integer is positive.
        totalBorrow[bucket] = uint(int(totalBorrow[bucket]) + amount);

        if (amount > 0) {
            checkHealth(msg.sender, bucket);
            require(totalBorrow[bucket] <= totalSupply[bucket], "not enough liquidity");
        }

        IERC20(borrowableAsset).handleTransfer({user: msg.sender, amountIn: -amount});
    }

    /// @dev positive amount to deposit.
    function modifyCollateral(int amount, uint bucket) external {
        if (amount == 0) return;
        require(bucket < N, "unknown bucket");

        accrueInterests(bucket);

        collateral[msg.sender][bucket] = (int(collateral[msg.sender][bucket]) + amount).safeToUint();

        if (amount < 0) checkHealth(msg.sender, bucket);

        IERC20(collateralAsset).handleTransfer({user: msg.sender, amountIn: amount});
    }

    // Interests management.

    function accrueInterests(uint bucket) internal {
        uint bucketTotalBorrow = totalBorrow[bucket];
        uint bucketTotalSupply = totalSupply[bucket];
        if (bucketTotalSupply == 0) return;
        uint utilization = bucketTotalBorrow.wDiv(bucketTotalSupply);
        uint borrowRate = irm(utilization);
        uint accruedInterests = bucketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - lastUpdate[bucket]);

        totalSupply[bucket] = bucketTotalSupply + accruedInterests;
        totalBorrow[bucket] = bucketTotalBorrow + accruedInterests;
        lastUpdate[bucket] = block.timestamp;
    }

    // Health check.

    function checkHealth(address user, uint bucket) public view {
        if (totalBorrowShares[bucket] > 0 && borrowShare[user][bucket] > 0) {
            uint borrowValue = borrowShare[user][bucket].wMul(totalBorrow[bucket]).wDiv(totalBorrowShares[bucket]).wMul(
                IOracle(borrowableOracle).price()
            );
            uint collateralValue = collateral[user][bucket].wMul(IOracle(collateralOracle).price());
            require(collateralValue.wMul(bucketToLLTV(bucket)) >= borrowValue, "not enough collateral");
        }
    }
}
