// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {SharesMath} from "./libraries/SharesMath.sol";
import {WadRayMath} from "morpho-utils/math/WadRayMath.sol";
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
    using SharesMath for uint256;
    using WadRayMath for uint256;
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

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, "LLTV too high");
        isLltvEnabled[lltv] = true;
    }

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = market.toId();
        require(isIrmEnabled[market.irm], "IRM not enabled");
        require(isLltvEnabled[market.lltv], "LLTV not enabled");
        require(lastUpdate[id] == 0, "market already exists");

        _accrueInterests(market, id);
    }

    // Supply management.

    function supply(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        _accrueInterests(market, id);

        uint256 marketTotalSupply = totalSupply[id];
        uint256 marketTotalSupplyShares = totalSupplyShares[id];
        uint256 shares = amount.toSharesDown(marketTotalSupply, marketTotalSupplyShares);

        supplyShare[id][msg.sender] += shares;
        totalSupplyShares[id] = marketTotalSupplyShares + shares;
        totalSupply[id] = marketTotalSupply + amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        _accrueInterests(market, id);

        uint256 marketTotalSupply = totalSupply[id];
        uint256 marketTotalSupplyShares = totalSupplyShares[id];
        uint256 shares = amount.toSharesUp(marketTotalSupply, marketTotalSupplyShares);

        marketTotalSupply -= amount;

        supplyShare[id][msg.sender] -= shares;
        totalSupplyShares[id] = marketTotalSupplyShares - shares;
        totalSupply[id] = marketTotalSupply;

        require(totalBorrow[id] <= marketTotalSupply, "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        _accrueInterests(market, id);

        uint256 marketTotalBorrow = totalBorrow[id];
        uint256 marketTotalBorrowShares = totalBorrowShares[id];
        uint256 shares = amount.toSharesUp(marketTotalBorrow, marketTotalBorrowShares);

        marketTotalBorrow += amount;

        borrowShare[id][msg.sender] += shares;
        totalBorrowShares[id] = marketTotalBorrowShares + shares;
        totalBorrow[id] = marketTotalBorrow;

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        require(_isHealthy(id, msg.sender, market.lltv, collateralPrice, borrowablePrice), "not enough collateral");
        require(marketTotalBorrow <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        _accrueInterests(market, id);

        _accountRepay(id, amount, msg.sender);

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][msg.sender] += amount;

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        _accrueInterests(market, id);

        collateral[id][msg.sender] -= amount;

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        require(_isHealthy(id, msg.sender, market.lltv, collateralPrice, borrowablePrice), "not enough collateral");

        market.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(Market calldata market, address borrower, uint256 seized) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(seized != 0, "zero amount");

        _accrueInterests(market, id);

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        require(
            !_isHealthy(id, borrower, market.lltv, collateralPrice, borrowablePrice),
            "cannot liquidate a healthy position"
        );

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.wadMulDown(WAD.wadDivDown(market.lltv) - WAD);
        uint256 repaid = seized.wadMulUp(collateralPrice).wadDivUp(incentive).wadDivUp(borrowablePrice);

        (uint256 shares, uint256 marketTotalBorrow, uint256 marketTotalBorrowShares) =
            _accountRepay(id, repaid, borrower);

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            totalSupply[id] -= shares.toAssetsUp(marketTotalBorrow, marketTotalBorrowShares);
            totalBorrowShares[id] = marketTotalBorrowShares - shares;
            borrowShare[id][borrower] = 0;
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);
        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Interests management.

    function _accrueInterests(Market calldata market, Id id) private {
        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.wadMulDown(borrowRate * (block.timestamp - lastUpdate[id]));
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
            totalSupply[id] += accruedInterests;
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function _isHealthy(Id id, address user, uint256 lltv, uint256 collateralPrice, uint256 borrowablePrice)
        private
        view
        returns (bool)
    {
        uint256 borrowShares = borrowShare[id][user];
        if (borrowShares == 0) return true;

        // totalBorrowShares[id] > 0 when borrowShares > 0.
        uint256 borrowValue = borrowShares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]).wadMulUp(borrowablePrice);
        uint256 collateralValue = collateral[id][user].wadMulDown(collateralPrice);
        return collateralValue.wadMulDown(lltv) >= borrowValue;
    }

    // Accounting.

    function _accountRepay(Id id, uint256 amount, address borrower)
        private
        returns (uint256 newShares, uint256 newTotalBorrow, uint256 newTotalBorrowShares)
    {
        newShares = borrowShare[id][borrower];
        newTotalBorrow = totalBorrow[id];
        newTotalBorrowShares = totalBorrowShares[id];

        uint256 shares = amount.toSharesDown(newTotalBorrow, newTotalBorrowShares);

        newShares -= shares;
        newTotalBorrow -= shares;
        newTotalBorrowShares -= shares;

        borrowShare[id][borrower] = newShares;
        totalBorrowShares[id] = newTotalBorrowShares;
        totalBorrow[id] = newTotalBorrow;
    }
}
