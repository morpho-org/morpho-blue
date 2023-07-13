// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {Errors} from "./libraries/Errors.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint256 constant WAD = 1e18;
uint256 constant ALPHA = 0.5e18;

// Market id.
type Id is bytes32;

// Market.
struct Market {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    IIrm irm;
    uint256 lltv;
}

using {toId} for Market;

function toId(Market calldata market) pure returns (Id) {
    return Id.wrap(keccak256(abi.encode(market)));
}

contract Blue {
    using MathLib for uint256;
    using SafeTransferLib for IERC20;

    // Storage.

    // Owner.
    address public owner;
    // User' supply balances.
    mapping(Id => mapping(address => uint256)) public supplyShare;
    // User' borrow balances.
    mapping(Id => mapping(address => uint256)) public borrowShare;
    // User' collateral balance.
    mapping(Id => mapping(address => uint256)) public collateral;
    // Market total supply.
    mapping(Id => uint256) public totalSupply;
    // Market total supply shares.
    mapping(Id => uint256) public totalSupplyShares;
    // Market total borrow.
    mapping(Id => uint256) public totalBorrow;
    // Market total borrow shares.
    mapping(Id => uint256) public totalBorrowShares;
    // Interests last update (used to check if a market has been created).
    mapping(Id => uint256) public lastUpdate;
    // Enabled IRMs.
    mapping(IIrm => bool) public isIrmEnabled;
    // Enabled LLTVs.
    mapping(uint256 => bool) public isLltvEnabled;

    // Constructor.

    constructor(address newOwner) {
        owner = newOwner;
    }

    // Modifiers.

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    // Only owner functions.

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function enableIrm(IIrm irm) external onlyOwner {
        isIrmEnabled[irm] = true;
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, Errors.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;
    }

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = market.toId();
        require(isIrmEnabled[market.irm], Errors.IRM_DISABLED);
        require(isLltvEnabled[market.lltv], Errors.LLTV_DISABLED);
        require(lastUpdate[id] == 0, Errors.MARKET_CREATED);

        accrueInterests(market, id);
    }

    // Supply management.

    function supply(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        accrueInterests(market, id);

        if (totalSupply[id] == 0) {
            supplyShare[id][msg.sender] = WAD;
            totalSupplyShares[id] = WAD;
        } else {
            uint256 shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
            supplyShare[id][msg.sender] += shares;
            totalSupplyShares[id] += shares;
        }

        totalSupply[id] += amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        accrueInterests(market, id);

        uint256 shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
        supplyShare[id][msg.sender] -= shares;
        totalSupplyShares[id] -= shares;

        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        accrueInterests(market, id);

        if (totalBorrow[id] == 0) {
            borrowShare[id][msg.sender] = WAD;
            totalBorrowShares[id] = WAD;
        } else {
            uint256 shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
            borrowShare[id][msg.sender] += shares;
            totalBorrowShares[id] += shares;
        }

        totalBorrow[id] += amount;

        require(isHealthy(market, id, msg.sender), Errors.INSUFFICIENT_COLLATERAL);
        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        accrueInterests(market, id);

        uint256 shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
        borrowShare[id][msg.sender] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][msg.sender] += amount;

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        accrueInterests(market, id);

        collateral[id][msg.sender] -= amount;

        require(isHealthy(market, id, msg.sender), Errors.INSUFFICIENT_COLLATERAL);

        market.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(Market calldata market, address borrower, uint256 seized) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(seized != 0, Errors.ZERO_AMOUNT);

        accrueInterests(market, id);

        require(!isHealthy(market, id, borrower), Errors.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.wMul(WAD.wDiv(market.lltv) - WAD);
        uint256 repaid =
            seized.wMul(market.collateralOracle.price()).wDiv(incentive).wDiv(market.borrowableOracle.price());
        uint256 repaidShares = repaid.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);

        borrowShare[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            uint256 badDebt = borrowShare[id][borrower].wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]);
            totalSupply[id] -= badDebt;
            totalBorrow[id] -= badDebt;
            totalBorrowShares[id] -= borrowShare[id][borrower];
            borrowShare[id][borrower] = 0;
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);
        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Interests management.

    function accrueInterests(Market calldata market, Id id) private {
        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - lastUpdate[id]);
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
            totalSupply[id] += accruedInterests;
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function isHealthy(Market calldata market, Id id, address user) private view returns (bool) {
        uint256 borrowShares = borrowShare[id][user];
        if (borrowShares == 0) return true;
        // totalBorrowShares[id] > 0 when borrowShares > 0.
        uint256 borrowValue =
            borrowShares.wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]).wMul(market.borrowableOracle.price());
        uint256 collateralValue = collateral[id][user].wMul(market.collateralOracle.price());
        return collateralValue.wMul(market.lltv) >= borrowValue;
    }
}
