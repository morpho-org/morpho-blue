// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {Id} from "../interfaces/IMorpho.sol";

/// @title WhitelistRegistry
/// @notice Manages whitelist of authorized liquidators for each market
/// @dev Each market maintains its own whitelist of liquidators
contract WhitelistRegistry {
    /* ERRORS */

    error Unauthorized();
    error AlreadySet();
    error InvalidAddress();
    error InvalidMarket();
    error MinLiquidatorsRequired();
    error MaxLiquidatorsExceeded();

    /* EVENTS */

    event LiquidatorAdded(Id indexed marketId, address indexed liquidator, uint256 timestamp);
    event LiquidatorRemoved(Id indexed marketId, address indexed liquidator, uint256 timestamp);
    event MarketAdminTransferred(Id indexed marketId, address indexed previousAdmin, address indexed newAdmin);
    event WhitelistModeSet(Id indexed marketId, bool enabled);
    event MinDepositSet(uint256 newMinDeposit);
    event MaxLiquidatorsSet(uint256 newMaxLiquidators);

    /* STORAGE */

    /// @notice The owner of the registry (super admin)
    address public owner;

    /// @notice Minimum deposit required for liquidators (in wei)
    uint256 public minDeposit;

    /// @notice Maximum number of liquidators per market
    uint256 public maxLiquidators;

    /// @notice Market ID => Admin address
    mapping(Id => address) public marketAdmin;

    /// @notice Market ID => Liquidator address => Is authorized
    mapping(Id => mapping(address => bool)) public isAuthorizedLiquidator;

    /// @notice Market ID => Is whitelist mode enabled
    mapping(Id => bool) public isWhitelistEnabled;

    /// @notice Market ID => List of liquidators
    mapping(Id => address[]) private liquidatorsList;

    /// @notice Liquidator address => Market ID => Join timestamp
    mapping(address => mapping(Id => uint256)) public liquidatorJoinTime;

    /// @notice Liquidator address => Market ID => Liquidation count
    mapping(address => mapping(Id => uint256)) public liquidationCount;

    /// @notice Liquidator address => Deposited amount
    mapping(address => uint256) public liquidatorDeposit;

    /// @notice Market ID => Admin address => Pending new admin
    mapping(Id => address) public pendingMarketAdmin;

    /// @notice Market ID => Admin transfer initiation time
    mapping(Id => uint256) public adminTransferInitiatedAt;

    /// @notice Timelock period for admin transfer (default 2 days)
    uint256 public adminTransferTimelock;

    /// @notice Liquidator address => Market ID => Slashed amount
    mapping(address => mapping(Id => uint256)) public slashedAmount;

    /* MODIFIERS */

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyMarketAdmin(Id marketId) {
        if (msg.sender != marketAdmin[marketId] && msg.sender != owner) revert Unauthorized();
        _;
    }

    /* CONSTRUCTOR */

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidAddress();
        owner = _owner;
        minDeposit = 1 ether; // Default 1 ETH
        maxLiquidators = 50; // Default max 50 liquidators per market
        adminTransferTimelock = 2 days; // Default 2 days timelock
    }

    /* OWNER FUNCTIONS */

    /// @notice Transfer ownership to a new owner
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        if (newOwner == owner) revert AlreadySet();
        owner = newOwner;
    }

    /// @notice Set minimum deposit required for liquidators
    /// @param newMinDeposit The new minimum deposit amount
    function setMinDeposit(uint256 newMinDeposit) external onlyOwner {
        minDeposit = newMinDeposit;
        emit MinDepositSet(newMinDeposit);
    }

    /// @notice Set maximum number of liquidators per market
    /// @param newMaxLiquidators The new maximum
    function setMaxLiquidators(uint256 newMaxLiquidators) external onlyOwner {
        maxLiquidators = newMaxLiquidators;
        emit MaxLiquidatorsSet(newMaxLiquidators);
    }

    /// @notice Set admin transfer timelock period
    /// @param newTimelock The new timelock period in seconds
    function setAdminTransferTimelock(uint256 newTimelock) external onlyOwner {
        adminTransferTimelock = newTimelock;
    }

    /* MARKET ADMIN FUNCTIONS */

    /// @notice Initialize a market with an admin
    /// @param marketId The market ID
    /// @param admin The admin address
    function initializeMarket(Id marketId, address admin) external {
        if (admin == address(0)) revert InvalidAddress();
        if (marketAdmin[marketId] != address(0)) revert AlreadySet();
        
        marketAdmin[marketId] = admin;
        emit MarketAdminTransferred(marketId, address(0), admin);
    }

    /// @notice Initiate market admin transfer (Step 1: propose)
    /// @param marketId The market ID
    /// @param newAdmin The new admin address
    function initiateMarketAdminTransfer(Id marketId, address newAdmin) external onlyMarketAdmin(marketId) {
        if (newAdmin == address(0)) revert InvalidAddress();
        if (newAdmin == marketAdmin[marketId]) revert AlreadySet();
        
        pendingMarketAdmin[marketId] = newAdmin;
        adminTransferInitiatedAt[marketId] = block.timestamp;
    }

    /// @notice Complete market admin transfer (Step 2: execute after timelock)
    /// @param marketId The market ID
    function completeMarketAdminTransfer(Id marketId) external {
        address newAdmin = pendingMarketAdmin[marketId];
        if (newAdmin == address(0)) revert InvalidAddress();
        
        uint256 initiatedAt = adminTransferInitiatedAt[marketId];
        if (block.timestamp < initiatedAt + adminTransferTimelock) revert InvalidAddress();
        
        address previousAdmin = marketAdmin[marketId];
        marketAdmin[marketId] = newAdmin;
        
        // Clear pending transfer
        delete pendingMarketAdmin[marketId];
        delete adminTransferInitiatedAt[marketId];
        
        emit MarketAdminTransferred(marketId, previousAdmin, newAdmin);
    }

    /// @notice Cancel pending admin transfer
    /// @param marketId The market ID
    function cancelMarketAdminTransfer(Id marketId) external onlyMarketAdmin(marketId) {
        delete pendingMarketAdmin[marketId];
        delete adminTransferInitiatedAt[marketId];
    }

    /// @notice Enable or disable whitelist mode for a market
    /// @param marketId The market ID
    /// @param enabled Whether to enable whitelist mode
    function setWhitelistMode(Id marketId, bool enabled) external onlyMarketAdmin(marketId) {
        if (marketAdmin[marketId] == address(0)) revert InvalidMarket();
        if (isWhitelistEnabled[marketId] == enabled) revert AlreadySet();
        
        isWhitelistEnabled[marketId] = enabled;
        emit WhitelistModeSet(marketId, enabled);
    }

    /// @notice Add a liquidator to the market whitelist
    /// @param marketId The market ID
    /// @param liquidator The liquidator address
    function addLiquidator(Id marketId, address liquidator) external onlyMarketAdmin(marketId) {
        if (liquidator == address(0)) revert InvalidAddress();
        if (marketAdmin[marketId] == address(0)) revert InvalidMarket();
        if (isAuthorizedLiquidator[marketId][liquidator]) revert AlreadySet();
        if (liquidatorsList[marketId].length >= maxLiquidators) revert MaxLiquidatorsExceeded();
        
        isAuthorizedLiquidator[marketId][liquidator] = true;
        liquidatorsList[marketId].push(liquidator);
        liquidatorJoinTime[liquidator][marketId] = block.timestamp;
        
        emit LiquidatorAdded(marketId, liquidator, block.timestamp);
    }

    /// @notice Remove a liquidator from the market whitelist
    /// @param marketId The market ID
    /// @param liquidator The liquidator address
    function removeLiquidator(Id marketId, address liquidator) external onlyMarketAdmin(marketId) {
        if (!isAuthorizedLiquidator[marketId][liquidator]) revert InvalidAddress();
        
        // Ensure at least one liquidator remains if whitelist is enabled
        if (isWhitelistEnabled[marketId] && liquidatorsList[marketId].length <= 1) {
            revert MinLiquidatorsRequired();
        }
        
        isAuthorizedLiquidator[marketId][liquidator] = false;
        
        // Remove from array
        address[] storage liquidators = liquidatorsList[marketId];
        for (uint256 i = 0; i < liquidators.length; i++) {
            if (liquidators[i] == liquidator) {
                liquidators[i] = liquidators[liquidators.length - 1];
                liquidators.pop();
                break;
            }
        }
        
        emit LiquidatorRemoved(marketId, liquidator, block.timestamp);
    }

    /// @notice Batch add liquidators to save gas
    /// @param marketId The market ID
    /// @param liquidators Array of liquidator addresses
    function batchAddLiquidators(Id marketId, address[] calldata liquidators) external onlyMarketAdmin(marketId) {
        if (marketAdmin[marketId] == address(0)) revert InvalidMarket();
        if (liquidatorsList[marketId].length + liquidators.length > maxLiquidators) {
            revert MaxLiquidatorsExceeded();
        }
        
        for (uint256 i = 0; i < liquidators.length; i++) {
            address liquidator = liquidators[i];
            if (liquidator == address(0)) revert InvalidAddress();
            if (isAuthorizedLiquidator[marketId][liquidator]) continue;
            
            isAuthorizedLiquidator[marketId][liquidator] = true;
            liquidatorsList[marketId].push(liquidator);
            liquidatorJoinTime[liquidator][marketId] = block.timestamp;
            
            emit LiquidatorAdded(marketId, liquidator, block.timestamp);
        }
    }

    /* LIQUIDATOR FUNCTIONS */

    /// @notice Deposit collateral as a liquidator
    function depositCollateral() external payable {
        liquidatorDeposit[msg.sender] += msg.value;
    }

    /// @notice Withdraw deposited collateral
    /// @param amount The amount to withdraw
    function withdrawCollateral(uint256 amount) external {
        if (liquidatorDeposit[msg.sender] < amount) revert InvalidAddress();
        liquidatorDeposit[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    /// @notice Slash liquidator deposit for malicious behavior
    /// @param marketId The market ID
    /// @param liquidator The liquidator address
    /// @param amount The amount to slash
    function slashLiquidator(Id marketId, address liquidator, uint256 amount) external onlyMarketAdmin(marketId) {
        if (liquidatorDeposit[liquidator] < amount) revert InvalidAddress();
        
        liquidatorDeposit[liquidator] -= amount;
        slashedAmount[liquidator][marketId] += amount;
        
        // Transfer slashed amount to market admin (or protocol treasury)
        payable(marketAdmin[marketId]).transfer(amount);
    }

    /* PUBLIC FUNCTIONS */

    /// @notice Record a liquidation (to be called by TieredLiquidationMorpho)
    /// @param marketId The market ID
    /// @param liquidator The liquidator address
    function recordLiquidation(Id marketId, address liquidator) external {
        liquidationCount[liquidator][marketId]++;
    }

    /* VIEW FUNCTIONS */

    /// @notice Check if a liquidator is authorized for a market
    /// @param marketId The market ID
    /// @param liquidator The liquidator address
    /// @return Whether the liquidator can liquidate on this market
    function canLiquidate(Id marketId, address liquidator) external view returns (bool) {
        // If whitelist is not enabled, anyone can liquidate
        if (!isWhitelistEnabled[marketId]) return true;
        
        // Market admin can always liquidate
        if (liquidator == marketAdmin[marketId] || liquidator == owner) return true;
        
        // Check if liquidator is in whitelist
        return isAuthorizedLiquidator[marketId][liquidator];
    }

    /// @notice Get all liquidators for a market
    /// @param marketId The market ID
    /// @return Array of liquidator addresses
    function getLiquidators(Id marketId) external view returns (address[] memory) {
        return liquidatorsList[marketId];
    }

    /// @notice Get liquidator count for a market
    /// @param marketId The market ID
    /// @return Number of liquidators
    function getLiquidatorCount(Id marketId) external view returns (uint256) {
        return liquidatorsList[marketId].length;
    }

    /// @notice Get detailed liquidator info
    /// @param marketId The market ID
    /// @param liquidator The liquidator address
    /// @return isAuthorized Whether the liquidator is authorized
    /// @return joinTime When the liquidator joined
    /// @return liquidations Number of liquidations performed
    /// @return deposit Deposited collateral amount
    function getLiquidatorInfo(Id marketId, address liquidator)
        external
        view
        returns (bool isAuthorized, uint256 joinTime, uint256 liquidations, uint256 deposit)
    {
        return (
            isAuthorizedLiquidator[marketId][liquidator],
            liquidatorJoinTime[liquidator][marketId],
            liquidationCount[liquidator][marketId],
            liquidatorDeposit[liquidator]
        );
    }
}

