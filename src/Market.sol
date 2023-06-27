// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint constant WAD = 1e18;

uint constant alpha = 0.5e18;

uint constant N = 10;

function bucketToLLTV(uint bucket) pure returns (uint) {
    return MathLib.wDiv(bucket + 1, N + 1);
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
            supplyShare[msg.sender][bucket] = WAD;
            totalSupplyShares[bucket] = WAD;
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
            borrowShare[msg.sender][bucket] = WAD;
            totalBorrowShares[bucket] = WAD;
        } else {
            int shares = amount.wMul(totalBorrowShares[bucket]).wDiv(totalBorrow[bucket]);
            borrowShare[msg.sender][bucket] = (int(borrowShare[msg.sender][bucket]) + shares).safeToUint();
            totalBorrowShares[bucket] = (int(totalBorrowShares[bucket]) + shares).safeToUint();
        }

        // No need to check if the integer is positive.
        totalBorrow[bucket] = uint(int(totalBorrow[bucket]) + amount);

        if (amount > 0) {
            require(isHealthy(msg.sender, bucket), "not enough collateral");
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

        require(amount > 0 || isHealthy(msg.sender, bucket), "not enough collateral");

        IERC20(collateralAsset).handleTransfer({user: msg.sender, amountIn: amount});
    }

    struct Liquidation {
        address borrower;
        uint bucket;
        uint maxCollat;
    }

    // @dev positive amount to seize.
    function batchLiquidate(Liquidation[] memory liquidations) external {
        int sumCollat;
        int sumBorrow;

        for (uint i; i < liquidations.length; i++) {
            Liquidation memory liq = liquidations[i];
            (int collat, int borrow) = _liquidate(liq.borrower, liq.bucket, liq.maxCollat);
            sumCollat += collat;
            sumBorrow += borrow;
        }

        IERC20(borrowableAsset).handleTransfer(msg.sender, sumBorrow);
        IERC20(collateralAsset).handleTransfer(msg.sender, sumCollat);
    }

    function _liquidate(address borrower, uint bucket, uint maxCollat) internal returns (int collat, int borrow) {
        accrueInterests(bucket);

        uint bucketLLTV = bucketToLLTV(bucket);
        require(!isHealthy(borrower, bucket), "Cannot liquidate a healthy position");

        uint incentive = WAD + alpha.wMul(WAD.wDiv(bucketLLTV) - WAD);
        uint borrowablePrice = IOracle(borrowableOracle).price();
        uint collateralPrice = IOracle(collateralOracle).price();
        maxCollat = maxCollat.min(collateral[borrower][bucket]);
        // Safe to cast to int because maxCollat <= collateral[borrower][bucket]
        collat = int(maxCollat);
        borrow = -(maxCollat.wMul(collateralPrice).wDiv(incentive).wDiv(borrowablePrice)).safeToInt();

        int shares = borrow.wMul(totalBorrowShares[bucket]).wDiv(totalBorrow[bucket]);
        borrowShare[borrower][bucket] = (int(borrowShare[borrower][bucket]) + shares).safeToUint();
        totalBorrowShares[bucket] = (int(totalBorrowShares[bucket]) + shares).safeToUint();
        totalBorrow[bucket] = (int(totalBorrow[bucket]) + borrow).safeToUint();
        collateral[borrower][bucket] = (int(collateral[borrower][bucket]) + collat).safeToUint();
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

    function isHealthy(address user, uint bucket) public view returns (bool) {
        if (borrowShare[user][bucket] > 0) {
            // totalBorrowShares[bucket] > 0 because borrowShare[user][bucket] > 0.
            uint borrowValue = borrowShare[user][bucket].wMul(totalBorrow[bucket]).wDiv(totalBorrowShares[bucket]).wMul(
                IOracle(borrowableOracle).price()
            );
            uint collateralValue = collateral[user][bucket].wMul(IOracle(collateralOracle).price());
            return collateralValue.wMul(bucketToLLTV(bucket)) >= borrowValue;
        }
        return true;
    }
}
