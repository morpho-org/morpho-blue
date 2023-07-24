// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {Errors} from "./libraries/Errors.sol";
import {SharesMath} from "src/libraries/SharesMath.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {Id, Market, MarketLib} from "src/libraries/MarketLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint256 constant WAD = 1e18;
uint256 constant MAX_FEE = 0.2e18;
uint256 constant ALPHA = 0.5e18;

contract Blue {
    using SharesMath for uint256;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for IERC20;
    using MarketLib for Market;

    // Storage.

    // Owner.
    address public owner;
    // Fee recipient.
    address public feeRecipient;
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
    // Fee.
    mapping(Id => uint256) public fee;
    // Enabled IRMs.
    mapping(IIrm => bool) public isIrmEnabled;
    // Enabled LLTVs.
    mapping(uint256 => bool) public isLltvEnabled;
    // User's managers.
    mapping(address => mapping(address => bool)) public isApproved;

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

    /// @notice It is the owner's responsibility to ensure a fee recipient is set before setting a non-zero fee.
    function setFee(Market calldata market, uint256 newFee) external onlyOwner {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, Errors.MAX_FEE_EXCEEDED);
        fee[id] = newFee;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;
    }

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = market.id();
        require(isIrmEnabled[market.irm], Errors.IRM_NOT_ENABLED);
        require(isLltvEnabled[market.lltv], Errors.LLTV_NOT_ENABLED);
        require(lastUpdate[id] == 0, Errors.MARKET_CREATED);

        _accrueInterests(market, id);
    }

    // Supply management.

    function supply(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesDown(totalSupply[id], totalSupplyShares[id]);
        supplyShare[id][onBehalf] += shares;
        totalSupplyShares[id] += shares;

        totalSupply[id] += amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderOrIsApproved(onBehalf), Errors.MANAGER_NOT_APPROVED);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesUp(totalSupply[id], totalSupplyShares[id]);
        supplyShare[id][onBehalf] -= shares;
        totalSupplyShares[id] -= shares;

        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderOrIsApproved(onBehalf), Errors.MANAGER_NOT_APPROVED);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesUp(totalBorrow[id], totalBorrowShares[id]);
        borrowShare[id][onBehalf] += shares;
        totalBorrowShares[id] += shares;

        totalBorrow[id] += amount;

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);
        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesDown(totalBorrow[id], totalBorrowShares[id]);
        borrowShare[id][onBehalf] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][onBehalf] += amount;

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderOrIsApproved(onBehalf), Errors.MANAGER_NOT_APPROVED);

        _accrueInterests(market, id);

        collateral[id][onBehalf] -= amount;

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);

        market.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(Market calldata market, address borrower, uint256 seized) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(seized != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        require(!_isHealthy(market, id, borrower, collateralPrice, borrowablePrice), Errors.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.mulWadDown(WAD.divWadDown(market.lltv) - WAD);
        uint256 repaid = seized.mulWadUp(collateralPrice).divWadUp(incentive).divWadUp(borrowablePrice);
        uint256 repaidShares = repaid.toSharesDown(totalBorrow[id], totalBorrowShares[id]);

        borrowShare[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            uint256 badDebt = borrowShare[id][borrower].toAssetsUp(totalBorrow[id], totalBorrowShares[id]);
            totalSupply[id] -= badDebt;
            totalBorrow[id] -= badDebt;
            totalBorrowShares[id] -= borrowShare[id][borrower];
            borrowShare[id][borrower] = 0;
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);
        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Position management.

    function setApproval(address manager, bool isAllowed) external {
        isApproved[msg.sender][manager] = isAllowed;
    }

    function _isSenderOrIsApproved(address user) internal view returns (bool) {
        return msg.sender == user || isApproved[user][msg.sender];
    }

    // Interests management.

    function _accrueInterests(Market calldata market, Id id) internal {
        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.mulWadDown(borrowRate * (block.timestamp - lastUpdate[id]));
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
            totalSupply[id] += accruedInterests;

            if (fee[id] != 0) {
                uint256 feeAmount = accruedInterests.mulWadDown(fee[id]);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.mulDivDown(totalSupplyShares[id], totalSupply[id] - feeAmount);
                supplyShare[id][feeRecipient] += feeShares;
                totalSupplyShares[id] += feeShares;
            }
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function _isHealthy(Market calldata market, Id id, address user) internal view returns (bool) {
        if (borrowShare[id][user] == 0) return true;

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        return _isHealthy(market, id, user, collateralPrice, borrowablePrice);
    }

    function _isHealthy(Market calldata market, Id id, address user, uint256 collateralPrice, uint256 borrowablePrice)
        internal
        view
        returns (bool)
    {
        uint256 borrowValue =
            borrowShare[id][user].toAssetsUp(totalBorrow[id], totalBorrowShares[id]).mulWadUp(borrowablePrice);
        uint256 collateralValue = collateral[id][user].mulWadDown(collateralPrice);

        return collateralValue.mulWadDown(market.lltv) >= borrowValue;
    }
}
