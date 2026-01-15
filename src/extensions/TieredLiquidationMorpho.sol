// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {Id, MarketParams, Position, Market} from "../interfaces/IMorpho.sol";
import {IMorpho} from "../interfaces/IMorpho.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {MathLib, WAD} from "../libraries/MathLib.sol";
import {SharesMathLib} from "../libraries/SharesMathLib.sol";
import {ORACLE_PRICE_SCALE} from "../libraries/ConstantsLib.sol";
import {MarketParamsLib} from "../libraries/MarketParamsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

import {WhitelistRegistry} from "./WhitelistRegistry.sol";
import {LiquidationTierLib} from "./libraries/LiquidationTierLib.sol";
import {HealthFactorLib} from "./libraries/HealthFactorLib.sol";
import {PriceOracleLib} from "./libraries/PriceOracleLib.sol";

/// @title TieredLiquidationMorpho
/// @notice Enhanced Morpho protocol with tiered liquidation mechanism
/// @dev Wraps Morpho Blue and adds multi-tier liquidation with whitelist control
contract TieredLiquidationMorpho {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using HealthFactorLib for uint256;
    using LiquidationTierLib for LiquidationTierLib.LiquidationTier[];
    using MarketParamsLib for MarketParams;

    /* ERRORS */

    error Unauthorized();
    error HealthyPosition();
    error InvalidLiquidationAmount();
    error ExceedsMaxLiquidation();
    error BelowMinimumSeized();
    error CooldownNotElapsed();
    error TieredLiquidationNotEnabled();
    error InvalidConfiguration();

    /* EVENTS */

    event TieredLiquidationExecuted(
        Id indexed marketId,
        address indexed liquidator,
        address indexed borrower,
        uint256 seizedAssets,
        uint256 repaidAssets,
        uint256 healthFactor,
        uint256 tierIndex,
        uint256 liquidationBonus
    );

    event MarketTiersConfigured(Id indexed marketId, uint256 tierCount, bool enabled);

    event LiquidationTierTriggered(
        Id indexed marketId, address indexed borrower, uint256 healthFactor, uint256 tierIndex
    );

    /* STORAGE */

    /// @notice The underlying Morpho protocol
    IMorpho public immutable morpho;

    /// @notice The whitelist registry
    WhitelistRegistry public immutable whitelistRegistry;

    /// @notice Owner of the contract
    address public owner;

    /// @notice Market ID => Liquidation configuration
    mapping(Id => LiquidationTierLib.MarketLiquidationConfig) private marketConfigs;

    /// @notice Market ID => Array of tiers
    mapping(Id => LiquidationTierLib.LiquidationTier[]) private marketTiers;

    /// @notice Market ID => Borrower => Last liquidation timestamp
    mapping(Id => mapping(address => uint256)) public lastLiquidationTime;

    /// @notice Market ID => Price oracle configuration
    mapping(Id => PriceOracleLib.PriceConfig) public priceConfigs;

    /// @notice Market ID => TWAP data
    mapping(Id => PriceOracleLib.TWAPData) public twapData;

    /// @notice Protocol fee recipient
    address public feeRecipient;

    /// @notice Market ID => Accumulated protocol fees
    mapping(Id => uint256) public accumulatedFees;

    /* MODIFIERS */

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /* CONSTRUCTOR */

    constructor(address _morpho, address _whitelistRegistry) {
        morpho = IMorpho(_morpho);
        whitelistRegistry = WhitelistRegistry(_whitelistRegistry);
        owner = msg.sender;
        feeRecipient = msg.sender; // Default to owner
    }

    /* OWNER FUNCTIONS */

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Set fee recipient
    /// @param newFeeRecipient The new fee recipient address
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid address");
        feeRecipient = newFeeRecipient;
    }

    /// @notice Configure price oracle for a market
    /// @param marketId The market ID
    /// @param config Price oracle configuration
    function configurePriceOracle(Id marketId, PriceOracleLib.PriceConfig memory config) external onlyOwner {
        priceConfigs[marketId] = config;
    }

    /// @notice Withdraw accumulated protocol fees
    /// @param marketId The market ID
    /// @param marketParams The market parameters
    function withdrawProtocolFees(Id marketId, MarketParams memory marketParams) external onlyOwner {
        uint256 fees = accumulatedFees[marketId];
        require(fees > 0, "No fees to withdraw");
        
        accumulatedFees[marketId] = 0;
        
        // Transfer fees in collateral token
        IERC20(marketParams.collateralToken).safeTransfer(feeRecipient, fees);
    }

    /// @notice Enable tiered liquidation for a market with default tiers
    /// @param marketId The market ID
    function enableTieredLiquidation(Id marketId) external onlyOwner {
        _configureDefaultTiers(marketId);
    }

    /// @notice Configure custom liquidation tiers for a market
    /// @param marketId The market ID
    /// @param tiers Array of liquidation tiers
    function configureTiers(Id marketId, LiquidationTierLib.LiquidationTier[] calldata tiers) external onlyOwner {
        if (tiers.length == 0) revert InvalidConfiguration();

        // Validate each tier
        for (uint256 i = 0; i < tiers.length; i++) {
            LiquidationTierLib.validateTier(tiers[i]);
        }

        // Validate tier ordering (descending thresholds)
        LiquidationTierLib.validateTierOrder(tiers);

        // Clear existing tiers
        delete marketTiers[marketId];

        // Add new tiers
        for (uint256 i = 0; i < tiers.length; i++) {
            marketTiers[marketId].push(tiers[i]);
        }

        // Enable tiered liquidation
        marketConfigs[marketId].enabled = true;

        emit MarketTiersConfigured(marketId, tiers.length, true);
    }

    /// @notice Disable tiered liquidation for a market
    /// @param marketId The market ID
    function disableTieredLiquidation(Id marketId) external onlyOwner {
        marketConfigs[marketId].enabled = false;
        emit MarketTiersConfigured(marketId, 0, false);
    }

    /* LIQUIDATION FUNCTIONS */

    /// @notice Liquidate a position with tiered liquidation rules
    /// @param marketParams The market parameters
    /// @param borrower The borrower to liquidate
    /// @param seizedAssets Amount of collateral to seize (0 to calculate from repaidShares)
    /// @param repaidShares Amount of debt shares to repay (0 to calculate from seizedAssets)
    /// @param data Callback data
    /// @return actualSeizedAssets Actual collateral seized
    /// @return actualRepaidAssets Actual debt repaid
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256 actualSeizedAssets, uint256 actualRepaidAssets) {
        Id marketId = marketParams.id();

        // If tiered liquidation is not enabled, pass through to Morpho
        // We need to act as a proxy: pull tokens from liquidator, approve Morpho, call it, and transfer collateral back
        if (!marketConfigs[marketId].enabled) {
            // Estimate the repay amount needed
            Market memory marketData = morpho.market(marketId);
            uint256 estimatedRepay;
            if (seizedAssets > 0) {
                // Rough estimation for seized assets
                uint256 collateralPrice = IOracle(marketParams.oracle).price();
                estimatedRepay = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE) * 12 / 10; // 120% buffer
            } else {
                estimatedRepay = repaidShares.toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares) * 12 / 10;
            }
            
            // Pull tokens from liquidator
            IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepay);
            
            // Approve Morpho
            (bool success,) = marketParams.loanToken.call(
                abi.encodeWithSignature("approve(address,uint256)", address(morpho), type(uint256).max)
            );
            require(success, "Approve failed");
            
            // Call Morpho liquidate
            (uint256 actualSeized, uint256 actualRepaid) = morpho.liquidate(marketParams, borrower, seizedAssets, repaidShares, data);
            
            // Return unused tokens to liquidator
            uint256 unusedAmount = estimatedRepay > actualRepaid ? estimatedRepay - actualRepaid : 0;
            if (unusedAmount > 0) {
                IERC20(marketParams.loanToken).safeTransfer(msg.sender, unusedAmount);
            }
            
            // Transfer seized collateral to liquidator
            IERC20(marketParams.collateralToken).safeTransfer(msg.sender, actualSeized);
            
            return (actualSeized, actualRepaid);
        }

        // Get market and position data
        Market memory marketData = morpho.market(marketId);
        Position memory pos = morpho.position(marketId, borrower);

        // Get validated price with oracle protection
        uint256 collateralPrice = _getValidatedPrice(marketId, marketParams);
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);
        uint256 healthFactor = HealthFactorLib.calculateHealthFactor(
            pos.collateral, collateralPrice, borrowed, marketParams.lltv
        );

        // Position must be unhealthy (HF < 1.0)
        // Note: Morpho Blue only allows liquidation when HF < 1.0
        // So our tiered system must work within this constraint
        if (healthFactor >= WAD) revert HealthyPosition();

        // Get configured tiers for this market
        LiquidationTierLib.LiquidationTier[] memory tiers = marketTiers[marketId];
        
        // Get applicable tier
        (LiquidationTierLib.LiquidationTier memory tier, uint256 tierIndex) =
            LiquidationTierLib.getTierForHealthFactor(tiers, healthFactor);

        emit LiquidationTierTriggered(marketId, borrower, healthFactor, tierIndex);

        // Check liquidator authorization based on tier settings
        // Tier settings override global whitelist mode
        if (tier.whitelistOnly) {
            // This tier requires whitelist - check if liquidator is authorized
            // Use canLiquidate which checks both whitelist and admin status
            bool isWhitelisted = whitelistRegistry.canLiquidate(marketId, msg.sender);
            
            // If global whitelist is enabled, canLiquidate works correctly
            // If global whitelist is disabled, we need to check manually
            if (!whitelistRegistry.isWhitelistEnabled(marketId)) {
                // Whitelist not globally enabled, check manually for this tier
                address[] memory liquidators = whitelistRegistry.getLiquidators(marketId);
                isWhitelisted = false;
                for (uint256 i = 0; i < liquidators.length; i++) {
                    if (liquidators[i] == msg.sender) {
                        isWhitelisted = true;
                        break;
                    }
                }
            }
            
            if (!isWhitelisted) {
                revert Unauthorized();
            }
        }
        // If tier.whitelistOnly is false, anyone can liquidate regardless of global whitelist mode

        // Check cooldown period
        uint256 lastLiquidation = lastLiquidationTime[marketId][borrower];
        if (tier.cooldownPeriod > 0 && lastLiquidation > 0) {
            if (block.timestamp < lastLiquidation + tier.cooldownPeriod) {
                revert CooldownNotElapsed();
            }
        }

        // Calculate liquidation limits
        (uint256 maxSeizableCollateral, uint256 maxRepayableDebt) = HealthFactorLib.calculateLiquidationLimits(
            pos.collateral, borrowed, tier.maxLiquidationRatio
        );

        // Calculate actual amounts based on tier limits and liquidation bonus
        uint256 liquidationIncentiveFactor = WAD + tier.liquidationBonus;

        if (seizedAssets > 0) {
            // Seize specified collateral, calculate debt to repay
            if (seizedAssets > maxSeizableCollateral) {
                revert ExceedsMaxLiquidation();
            }
            if (seizedAssets < tier.minSeizedAssets) {
                revert BelowMinimumSeized();
            }

            uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
            repaidShares = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor).toSharesUp(
                marketData.totalBorrowAssets, marketData.totalBorrowShares
            );

            actualSeizedAssets = seizedAssets;
        } else if (repaidShares > 0) {
            // Repay specified debt, calculate collateral to seize
            uint256 repaidAmount =
                repaidShares.toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);

            if (repaidAmount > maxRepayableDebt) {
                revert ExceedsMaxLiquidation();
            }

            actualSeizedAssets = repaidAmount.wMulDown(liquidationIncentiveFactor).mulDivDown(
                ORACLE_PRICE_SCALE, collateralPrice
            );

            if (actualSeizedAssets < tier.minSeizedAssets) {
                revert BelowMinimumSeized();
            }
            if (actualSeizedAssets > maxSeizableCollateral) {
                revert ExceedsMaxLiquidation();
            }
        } else {
            revert InvalidLiquidationAmount();
        }

        // Update last liquidation time
        lastLiquidationTime[marketId][borrower] = block.timestamp;

        // Record liquidation in whitelist registry
        whitelistRegistry.recordLiquidation(marketId, msg.sender);

        // Calculate estimated repay amount
        uint256 estimatedRepayAmount;
        if (actualSeizedAssets > 0) {
            uint256 seizedAssetsQuoted = actualSeizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
            estimatedRepayAmount = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor) * 11 / 10; // 110% buffer
        } else {
            estimatedRepayAmount = repaidShares.toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares) * 11 / 10;
        }
        
        // Pull loan tokens from liquidator
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepayAmount);
        
        // Approve Morpho to spend loan tokens
        (bool success,) = marketParams.loanToken.call(
            abi.encodeWithSignature("approve(address,uint256)", address(morpho), type(uint256).max)
        );
        require(success, "Approve failed");
        
        // Execute liquidation on underlying Morpho
        // Note: Morpho only allows liquidation when HF < 1.0
        // Note: Morpho requires exactly one of seizedAssets or repaidShares to be zero
        if (actualSeizedAssets > 0) {
            (actualSeizedAssets, actualRepaidAssets) =
                morpho.liquidate(marketParams, borrower, actualSeizedAssets, 0, "");
        } else {
            (actualSeizedAssets, actualRepaidAssets) =
                morpho.liquidate(marketParams, borrower, 0, repaidShares, "");
        }
        
        // Return unused loan tokens to liquidator
        uint256 unusedAmount = estimatedRepayAmount - actualRepaidAssets;
        if (unusedAmount > 0) {
            IERC20(marketParams.loanToken).safeTransfer(msg.sender, unusedAmount);
        }

        // Calculate and collect protocol fee
        if (tier.protocolFee > 0) {
            uint256 protocolFeeAmount = actualSeizedAssets.wMulDown(tier.protocolFee);
            if (protocolFeeAmount > 0) {
                accumulatedFees[marketId] += protocolFeeAmount;
                actualSeizedAssets -= protocolFeeAmount; // Reduce liquidator's share
            }
        }

        emit TieredLiquidationExecuted(
            marketId,
            msg.sender,
            borrower,
            actualSeizedAssets,
            actualRepaidAssets,
            healthFactor,
            tierIndex,
            tier.liquidationBonus
        );

        // Note: Morpho.liquidate already handles all token transfers
        // No need to transfer tokens again here

        return (actualSeizedAssets, actualRepaidAssets);
    }

    /* VIEW FUNCTIONS */

    /// @notice Get the health factor for a borrower
    /// @param marketParams The market parameters
    /// @param borrower The borrower address
    /// @return healthFactor The current health factor
    function getHealthFactor(MarketParams memory marketParams, address borrower)
        external
        view
        returns (uint256 healthFactor)
    {
        Id marketId = marketParams.id();
        Market memory marketData = morpho.market(marketId);
        Position memory pos = morpho.position(marketId, borrower);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);

        return HealthFactorLib.calculateHealthFactor(pos.collateral, collateralPrice, borrowed, marketParams.lltv);
    }

    /// @notice Get the applicable liquidation tier for a borrower
    /// @param marketParams The market parameters
    /// @param borrower The borrower address
    /// @return tier The applicable tier
    /// @return tierIndex The tier index
    function getApplicableTier(MarketParams memory marketParams, address borrower)
        external
        view
        returns (LiquidationTierLib.LiquidationTier memory tier, uint256 tierIndex)
    {
        Id marketId = marketParams.id();

        if (!marketConfigs[marketId].enabled) {
            revert TieredLiquidationNotEnabled();
        }

        Market memory marketData = morpho.market(marketId);
        Position memory pos = morpho.position(marketId, borrower);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);
        uint256 healthFactor = HealthFactorLib.calculateHealthFactor(
            pos.collateral, collateralPrice, borrowed, marketParams.lltv
        );

        return LiquidationTierLib.getTierForHealthFactor(marketTiers[marketId], healthFactor);
    }

    /// @notice Check if tiered liquidation is enabled for a market
    /// @param marketId The market ID
    /// @return enabled Whether tiered liquidation is enabled
    function isTieredLiquidationEnabled(Id marketId) external view returns (bool enabled) {
        return marketConfigs[marketId].enabled;
    }

    /// @notice Get all tiers for a market
    /// @param marketId The market ID
    /// @return tiers Array of liquidation tiers
    function getMarketTiers(Id marketId) external view returns (LiquidationTierLib.LiquidationTier[] memory tiers) {
        return marketTiers[marketId];
    }

    /* INTERNAL FUNCTIONS */

    /// @notice Configure default two-tier liquidation for a market
    /// @param marketId The market ID
    function _configureDefaultTiers(Id marketId) internal {
        // Clear existing tiers
        delete marketTiers[marketId];

        // Create default tiers
        (LiquidationTierLib.LiquidationTier memory tier1, LiquidationTierLib.LiquidationTier memory tier2) =
            LiquidationTierLib.createDefaultTiers();

        // Add tiers (must be in descending order of threshold)
        marketTiers[marketId].push(tier1); // HF < 1.1
        marketTiers[marketId].push(tier2); // HF < 1.0

        // Enable tiered liquidation
        marketConfigs[marketId].enabled = true;

        emit MarketTiersConfigured(marketId, 2, true);
    }

    /// @notice Get validated price with oracle protection
    /// @param marketId The market ID
    /// @param marketParams The market parameters
    /// @return price Validated collateral price
    function _getValidatedPrice(Id marketId, MarketParams memory marketParams) internal returns (uint256 price) {
        PriceOracleLib.PriceConfig memory config = priceConfigs[marketId];

        // If no custom config, use default (single oracle, no validation)
        if (config.primaryOracle == address(0)) {
            config.primaryOracle = marketParams.oracle;
            config.maxDeviation = 0.05e18; // 5% default
            config.useTWAP = false;
        }

        // Get validated price
        price = PriceOracleLib.getValidatedPrice(config);

        // Update TWAP if enabled
        if (config.useTWAP) {
            PriceOracleLib.TWAPData memory currentTwap = twapData[marketId];
            twapData[marketId] = PriceOracleLib.updateTWAP(currentTwap, price);
            
            // Use TWAP price if available
            if (currentTwap.lastUpdateTime > 0) {
                price = PriceOracleLib.calculateTWAP(twapData[marketId], config.twapPeriod);
            }
        }

        return price;
    }
}

