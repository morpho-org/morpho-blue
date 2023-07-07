// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint constant WAD = 1e18;
uint constant ALPHA = 0.5e18;

// Market id.
type Id is bytes32;

struct MarketParams {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    uint lLTV;
}

struct Market {
    uint totalSupply;
    uint totalBorrow;
    uint totalSupplyShares;
    uint totalBorrowShares;
    uint lastUpdate;
    uint fee; // in WAD
}

struct Position {
    uint supplyShare;
    uint borrowShare;
    uint collateral;
}

struct MarketStorage {
    Market market;
    mapping(address user => Position) position;
}

using {toId} for MarketParams;

function toId(MarketParams calldata marketParams) pure returns (Id) {
    return Id.wrap(keccak256(abi.encode(marketParams)));
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

    mapping(Id => MarketStorage) internal _marketStorage;
    address public feeRecipient;
    address public owner;

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

    // Markets management.

    function createMarket(MarketParams calldata marketParams, uint fee) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        require(m.lastUpdate == 0, "market already exists");
        m.fee = fee;

        accrueInterests(id);
    }

    // Getters.

    function getMarket(Id id) external view returns (Market memory) {
        return _marketStorage[id].market;
    }

    function getPosition(Id id, address user) external view returns (Position memory) {
        return _marketStorage[id].position[user];
    }

    // Supply management.

    function supply(MarketParams calldata marketParams, uint amount) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[msg.sender];

        require(m.lastUpdate != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(id);

        if (m.totalSupply == 0) {
            p.supplyShare = WAD;
            m.totalSupplyShares = WAD;
        } else {
            uint shares = amount.wMul(m.totalSupplyShares).wDiv(m.totalSupply);
            p.supplyShare += shares;
            m.totalSupplyShares += shares;
        }

        m.totalSupply += amount;

        marketParams.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(MarketParams calldata marketParams, uint amount) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[msg.sender];

        require(m.lastUpdate != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(id);

        uint shares = amount.wMul(m.totalSupplyShares).wDiv(m.totalSupply);
        p.supplyShare -= shares;
        m.totalSupplyShares -= shares;

        m.totalSupply -= amount;

        require(m.totalBorrow <= m.totalSupply, "not enough liquidity");

        marketParams.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(MarketParams calldata marketParams, uint amount) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[msg.sender];

        require(m.lastUpdate != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(id);

        if (m.totalBorrow == 0) {
            p.borrowShare = WAD;
            m.totalBorrowShares = WAD;
        } else {
            uint shares = amount.wMul(m.totalBorrowShares).wDiv(m.totalBorrow);
            p.borrowShare += shares;
            m.totalBorrowShares += shares;
        }

        m.totalBorrow += amount;

        require(isHealthy(marketParams, id, msg.sender), "not enough collateral");
        require(m.totalBorrow <= m.totalSupply, "not enough liquidity");

        marketParams.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(MarketParams calldata marketParams, uint amount) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[msg.sender];
        require(m.lastUpdate != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(id);

        uint shares = amount.wMul(m.totalBorrowShares).wDiv(m.totalBorrow);
        p.borrowShare -= shares;
        m.totalBorrowShares -= shares;

        m.totalBorrow -= amount;

        marketParams.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(MarketParams calldata marketParams, uint amount) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[msg.sender];

        require(m.lastUpdate != 0, "unknown market");
        require(amount != 0, "zero amount");

        // Don't accrue interests because it's not required and it saves gas.

        p.collateral += amount;

        marketParams.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(MarketParams calldata marketParams, uint amount) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[msg.sender];
        require(m.lastUpdate != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(id);

        p.collateral -= amount;

        require(isHealthy(marketParams, id, msg.sender), "not enough collateral");

        marketParams.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(MarketParams calldata marketParams, address borrower, uint seized) external {
        Id id = marketParams.toId();
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[borrower];

        require(m.lastUpdate != 0, "unknown market");
        require(seized != 0, "zero amount");

        accrueInterests(id);

        require(!isHealthy(marketParams, id, borrower), "cannot liquidate a healthy position");

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint incentive = WAD + ALPHA.wMul(WAD.wDiv(marketParams.lLTV) - WAD);
        uint repaid = seized.wMul(marketParams.collateralOracle.price()).wDiv(incentive).wDiv(
            marketParams.borrowableOracle.price()
        );
        uint repaidShares = repaid.wMul(m.totalBorrowShares).wDiv(m.totalBorrow);

        p.borrowShare -= repaidShares;
        m.totalBorrowShares -= repaidShares;
        m.totalBorrow -= repaid;

        p.collateral -= seized;

        // Realize the bad debt if needed.
        if (p.collateral == 0) {
            m.totalSupply -= p.borrowShare.wMul(m.totalBorrow).wDiv(m.totalBorrowShares);
            m.totalBorrowShares -= p.borrowShare;
            p.borrowShare = 0;
        }

        marketParams.collateralAsset.safeTransfer(msg.sender, seized);
        marketParams.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Interests management.

    function accrueInterests(Id id) private {
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        uint marketTotalSupply = m.totalSupply;

        if (marketTotalSupply != 0) {
            uint marketTotalBorrow = m.totalBorrow;
            uint utilization = marketTotalBorrow.wDiv(marketTotalSupply);
            uint borrowRate = irm(utilization);
            uint accruedInterests = marketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - m.lastUpdate);
            m.totalSupply = marketTotalSupply + accruedInterests;
            m.totalBorrow = marketTotalBorrow + accruedInterests;
            if (m.fee != 0) {
                uint fee = accruedInterests.wMul(m.fee);
                uint feeShares = fee.wMul(m.totalSupplyShares).wDiv(m.totalSupply - fee);
                s.position[feeRecipient].supplyShare += feeShares;
                m.totalSupplyShares += feeShares;
            }
        }

        m.lastUpdate = block.timestamp;
    }

    // Health check.

    function isHealthy(MarketParams calldata marketParams, Id id, address user) private view returns (bool) {
        MarketStorage storage s = _marketStorage[id];
        Market storage m = s.market;
        Position storage p = s.position[user];
        uint borrowShares = p.borrowShare;
        if (borrowShares == 0) return true;
        // totalBorrowShares > 0 when borrowShares > 0.
        uint borrowValue =
            borrowShares.wMul(m.totalBorrow).wDiv(m.totalBorrowShares).wMul(marketParams.borrowableOracle.price());
        uint collateralValue = p.collateral.wMul(marketParams.collateralOracle.price());
        return collateralValue.wMul(marketParams.lLTV) >= borrowValue;
    }
}
