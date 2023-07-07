// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint constant WAD = 1e18;
uint constant ALPHA = 0.5e18;

// Market id.
type Id is bytes32;

// Market.
struct Market {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    IIrm irm;
    uint lLTV;
}

using {toId} for Market;

function toId(Market calldata market) pure returns (Id) {
    return Id.wrap(keccak256(abi.encode(market)));
}

contract Blue {
    using MathLib for uint;
    using SafeTransferLib for IERC20;

    // Storage.

    // Owner.
    address public owner;
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
    // Enabled IRMs.
    mapping(IIrm => bool) public isIrmEnabled;

    // Constructor.

    constructor(address newOwner) {
        owner = newOwner;
    }

    // Modifiers.

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // Only owner functions.

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function enableIrm(IIrm irm) external onlyOwner {
        isIrmEnabled[irm] = true;
    }

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = market.toId();
        require(isIrmEnabled[market.irm], "IRM not enabled");
        require(lastUpdate[id] == 0, "market already exists");

        accrueInterests(market);
    }

    // Supply management.

    function supply(Market calldata market, uint amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market);

        if (totalSupply[id] == 0) {
            supplyShare[id][msg.sender] = WAD;
            totalSupplyShares[id] = WAD;
        } else {
            uint shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
            supplyShare[id][msg.sender] += shares;
            totalSupplyShares[id] += shares;
        }

        totalSupply[id] += amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market);

        uint shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
        supplyShare[id][msg.sender] -= shares;
        totalSupplyShares[id] -= shares;

        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market);

        if (totalBorrow[id] == 0) {
            borrowShare[id][msg.sender] = WAD;
            totalBorrowShares[id] = WAD;
        } else {
            uint shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
            borrowShare[id][msg.sender] += shares;
            totalBorrowShares[id] += shares;
        }

        totalBorrow[id] += amount;

        require(isHealthy(market, id, msg.sender), "not enough collateral");
        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market);

        uint shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
        borrowShare[id][msg.sender] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market calldata market, uint amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][msg.sender] += amount;

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market);

        collateral[id][msg.sender] -= amount;

        require(isHealthy(market, id, msg.sender), "not enough collateral");

        market.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(Market calldata market, address borrower, uint seized) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(seized != 0, "zero amount");

        accrueInterests(market);

        require(!isHealthy(market, id, borrower), "cannot liquidate a healthy position");

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint incentive = WAD + ALPHA.wMul(WAD.wDiv(market.lLTV) - WAD);
        uint repaid = seized.wMul(market.collateralOracle.price()).wDiv(incentive).wDiv(market.borrowableOracle.price());
        uint repaidShares = repaid.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);

        borrowShare[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            totalSupply[id] -= borrowShare[id][borrower].wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]);
            totalBorrowShares[id] -= borrowShare[id][borrower];
            borrowShare[id][borrower] = 0;
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);
        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Interests management.

    function accrueInterests(Market calldata market) private {
        Id id = market.toId();
        uint marketTotalSupply = totalSupply[id];

        if (marketTotalSupply != 0) {
            uint marketTotalBorrow = totalBorrow[id];
            uint borrowRate = market.irm.borrowRate(market);
            uint accruedInterests = marketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - lastUpdate[id]);
            totalSupply[id] = marketTotalSupply + accruedInterests;
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function isHealthy(Market calldata market, Id id, address user) private view returns (bool) {
        uint borrowShares = borrowShare[id][user];
        if (borrowShares == 0) return true;
        // totalBorrowShares[id] > 0 when borrowShares > 0.
        uint borrowValue =
            borrowShares.wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]).wMul(market.borrowableOracle.price());
        uint collateralValue = collateral[id][user].wMul(market.collateralOracle.price());
        return collateralValue.wMul(market.lLTV) >= borrowValue;
    }
}
