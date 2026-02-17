// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {Id} from "../interfaces/IMorpho.sol";

/// @title WhitelistRegistry
/// @notice Per-market whitelist of authorized liquidators
contract WhitelistRegistry {
    error Unauthorized();
    error AlreadySet();
    error InvalidAddress();
    error InvalidMarket();
    error MinLiquidatorsRequired();
    error MaxLiquidatorsExceeded();

    event LiquidatorAdded(Id indexed marketId, address indexed liquidator);
    event LiquidatorRemoved(Id indexed marketId, address indexed liquidator);
    event MarketAdminTransferred(Id indexed marketId, address indexed previousAdmin, address indexed newAdmin);
    event WhitelistModeSet(Id indexed marketId, bool enabled);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public owner;
    uint256 public maxLiquidators;

    /// @notice Authorized caller that can record liquidations (TieredLiquidationMorpho)
    address public authorizedCaller;

    mapping(Id => address) public marketAdmin;
    mapping(Id => mapping(address => bool)) public isAuthorizedLiquidator;
    mapping(Id => bool) public isWhitelistEnabled;
    mapping(Id => address[]) private liquidatorsList;
    mapping(address => mapping(Id => uint256)) public liquidationCount;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyMarketAdmin(Id marketId) {
        if (msg.sender != marketAdmin[marketId] && msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidAddress();
        owner = _owner;
        maxLiquidators = 50;
    }

    /* ── Owner Functions ───────────────────────────────────── */

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        if (newOwner == owner) revert AlreadySet();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setMaxLiquidators(uint256 newMax) external onlyOwner {
        maxLiquidators = newMax;
    }

    /// @notice Set the authorized caller (TieredLiquidationMorpho contract)
    function setAuthorizedCaller(address caller) external onlyOwner {
        if (caller == address(0)) revert InvalidAddress();
        authorizedCaller = caller;
    }

    /// @notice Initialize a market with an admin (owner-only to prevent front-running)
    function initializeMarket(Id marketId, address admin) external onlyOwner {
        if (admin == address(0)) revert InvalidAddress();
        if (marketAdmin[marketId] != address(0)) revert AlreadySet();
        marketAdmin[marketId] = admin;
        emit MarketAdminTransferred(marketId, address(0), admin);
    }

    /* ── Market Admin Functions ─────────────────────────────── */

    function transferMarketAdmin(Id marketId, address newAdmin) external onlyMarketAdmin(marketId) {
        if (newAdmin == address(0)) revert InvalidAddress();
        if (newAdmin == marketAdmin[marketId]) revert AlreadySet();
        emit MarketAdminTransferred(marketId, marketAdmin[marketId], newAdmin);
        marketAdmin[marketId] = newAdmin;
    }

    function setWhitelistMode(Id marketId, bool enabled) external onlyMarketAdmin(marketId) {
        if (marketAdmin[marketId] == address(0)) revert InvalidMarket();
        if (isWhitelistEnabled[marketId] == enabled) revert AlreadySet();
        isWhitelistEnabled[marketId] = enabled;
        emit WhitelistModeSet(marketId, enabled);
    }

    function addLiquidator(Id marketId, address liquidator) external onlyMarketAdmin(marketId) {
        if (liquidator == address(0)) revert InvalidAddress();
        if (marketAdmin[marketId] == address(0)) revert InvalidMarket();
        if (isAuthorizedLiquidator[marketId][liquidator]) revert AlreadySet();
        if (liquidatorsList[marketId].length >= maxLiquidators) revert MaxLiquidatorsExceeded();

        isAuthorizedLiquidator[marketId][liquidator] = true;
        liquidatorsList[marketId].push(liquidator);
        emit LiquidatorAdded(marketId, liquidator);
    }

    function removeLiquidator(Id marketId, address liquidator) external onlyMarketAdmin(marketId) {
        if (!isAuthorizedLiquidator[marketId][liquidator]) revert InvalidAddress();
        if (isWhitelistEnabled[marketId] && liquidatorsList[marketId].length <= 1) {
            revert MinLiquidatorsRequired();
        }

        isAuthorizedLiquidator[marketId][liquidator] = false;
        address[] storage list = liquidatorsList[marketId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == liquidator) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
        emit LiquidatorRemoved(marketId, liquidator);
    }

    /* ── Authorized Caller Functions ───────────────────────── */

    /// @notice Record a liquidation (restricted to authorized caller)
    function recordLiquidation(Id marketId, address liquidator) external {
        if (msg.sender != authorizedCaller) revert Unauthorized();
        liquidationCount[liquidator][marketId]++;
    }

    /* ── View Functions ─────────────────────────────────────── */

    function canLiquidate(Id marketId, address liquidator) external view returns (bool) {
        if (!isWhitelistEnabled[marketId]) return true;
        if (liquidator == marketAdmin[marketId] || liquidator == owner) return true;
        return isAuthorizedLiquidator[marketId][liquidator];
    }

    function getLiquidators(Id marketId) external view returns (address[] memory) {
        return liquidatorsList[marketId];
    }

    function getLiquidatorCount(Id marketId) external view returns (uint256) {
        return liquidatorsList[marketId].length;
    }
}
