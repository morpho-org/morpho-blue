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
import {HealthFactorLib} from "./libraries/HealthFactorLib.sol";
import {PriceOracleLib} from "./libraries/PriceOracleLib.sol";

/// @title TieredLiquidationMorpho
/// @notice Enhanced Morpho protocol with flexible liquidation mechanism
/// @dev Implements two-step liquidation with configurable parameters (no tiers)
contract TieredLiquidationMorpho {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using MarketParamsLib for MarketParams;

    /* ERRORS */

    error Unauthorized();
    error HealthyPosition();
    error InvalidLiquidationAmount();
    error ExceedsMaxLiquidation();
    error BelowMinimumSeized();
    error CooldownNotElapsed();
    error MarketNotConfigured();
    error InvalidConfiguration();
    error InvalidLiquidationStatus();
    error NotLiquidator();
    error InvalidLiquidationRatio();

    /* EVENTS */

    event LiquidationExecuted(
        Id indexed marketId,
        address indexed liquidator,
        address indexed borrower,
        uint256 seizedAssets,
        uint256 repaidAssets,
        uint256 healthFactor,
        uint256 liquidationBonus
    );

    event LiquidationRequested(
        Id indexed marketId,
        address indexed borrower,
        address indexed liquidator,
        uint256 repaidAmount,
        uint256 seizedCollateral,
        uint256 protocolFee,
        uint256 liquidationRatio
    );

    event LiquidationCompleted(
        Id indexed marketId,
        address indexed borrower,
        address indexed liquidator
    );

    event MarketConfigured(
        Id indexed marketId,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio,
        uint256 cooldownPeriod,
        uint256 minSeizedAssets,
        bool whitelistEnabled
    );

    /* STORAGE */

    /// @notice Liquidation status enum
    enum LiquidationStatus {
        None,
        Pending,
        Completed
    }

    /// @notice Market configuration (single tier, no multi-tier logic)
    struct MarketConfig {
        bool enabled;
        uint256 liquidationBonus;       // e.g., 0.1e18 = 10%
        uint256 maxLiquidationRatio;    // e.g., 1e18 = 100%
        uint256 cooldownPeriod;         // Seconds
        uint256 minSeizedAssets;        // Minimum collateral to seize
        bool whitelistEnabled;          // Optional whitelist
        uint256 protocolFee;            // Protocol fee rate (0.5e18 = 50%)
    }

    /// @notice The underlying Morpho protocol
    IMorpho public immutable morpho;

    /// @notice The whitelist registry
    WhitelistRegistry public immutable whitelistRegistry;

    /// @notice Owner of the contract
    address public owner;

    /// @notice Market ID => Liquidation configuration
    mapping(Id => MarketConfig) public marketConfigs;

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

    /// @notice Two-step liquidation tracking
    mapping(Id => mapping(address => LiquidationStatus)) public liquidationStatus;
    mapping(Id => mapping(address => address)) public liquidatorAddress;
    mapping(Id => mapping(address => uint256)) public pendingSeizedCollateral;

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

    /// @notice Configure market liquidation parameters (single configuration, no tiers)
    function configureMarket(
        Id marketId,
        bool enabled,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio,
        uint256 cooldownPeriod,
        uint256 minSeizedAssets,
        bool whitelistEnabled
    ) external onlyOwner {
        require(liquidationBonus <= 0.2e18, "Bonus too high"); // Max 20%
        require(maxLiquidationRatio <= WAD, "Ratio exceeds 100%");

        marketConfigs[marketId] = MarketConfig({
            enabled: enabled,
            liquidationBonus: liquidationBonus,
            maxLiquidationRatio: maxLiquidationRatio,
            cooldownPeriod: cooldownPeriod,
            minSeizedAssets: minSeizedAssets,
            whitelistEnabled: whitelistEnabled,
            protocolFee: 0.5e18  // Fixed 50/50 split
        });

        emit MarketConfigured(
            marketId,
            liquidationBonus,
            maxLiquidationRatio,
            cooldownPeriod,
            minSeizedAssets,
            whitelistEnabled
        );
    }

        /* LIQUIDATION FUNCTIONS */

    /// @notice Standard liquidation (no tiers, just single configuration)
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256 actualSeizedAssets, uint256 actualRepaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];

        if (!config.enabled) revert MarketNotConfigured();

        // Get position data
        Market memory marketData = morpho.market(marketId);
        Position memory pos = morpho.position(marketId, borrower);

        // Validate price and calculate health factor
        uint256 collateralPrice = _getValidatedPrice(marketId, marketParams);
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(
            marketData.totalBorrowAssets,
            marketData.totalBorrowShares
        );
        uint256 healthFactor = HealthFactorLib.calculateHealthFactor(
            pos.collateral,
            collateralPrice,
            borrowed,
            marketParams.lltv
        );

        // Must be unhealthy
        if (healthFactor >= WAD) revert HealthyPosition();

        // Check whitelist
        if (config.whitelistEnabled && !whitelistRegistry.canLiquidate(marketId, msg.sender)) {
            revert Unauthorized();
        }

        // Check cooldown
        if (config.cooldownPeriod > 0 && lastLiquidationTime[marketId][borrower] > 0) {
            if (block.timestamp < lastLiquidationTime[marketId][borrower] + config.cooldownPeriod) {
                revert CooldownNotElapsed();
            }
        }

        // Calculate liquidation limits
        (uint256 maxSeizableCollateral, uint256 maxRepayableDebt) =
            HealthFactorLib.calculateLiquidationLimits(pos.collateral, borrowed, config.maxLiquidationRatio);

        uint256 liquidationIncentiveFactor = WAD + config.liquidationBonus;

        if (seizedAssets > 0) {
            if (seizedAssets > maxSeizableCollateral) revert ExceedsMaxLiquidation();
            if (seizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();

            uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
            repaidShares = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor).toSharesUp(
                marketData.totalBorrowAssets,
                marketData.totalBorrowShares
            );
        } else if (repaidShares > 0) {
            uint256 repaidAmount = repaidShares.toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);
            if (repaidAmount > maxRepayableDebt) revert ExceedsMaxLiquidation();

            seizedAssets = repaidAmount.wMulDown(liquidationIncentiveFactor).mulDivDown(
                ORACLE_PRICE_SCALE,
                collateralPrice
            );

            if (seizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();
        } else {
            revert InvalidLiquidationAmount();
        }

        // Pull loan tokens
        uint256 estimatedRepayAmount = repaidShares.toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares) * 12 / 10;
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepayAmount);

        // Approve Morpho
        (bool success,) = marketParams.loanToken.call(
            abi.encodeWithSignature("approve(address,uint256)", address(morpho), type(uint256).max)
        );
        require(success, "Approve failed");

        // Execute liquidation
        (actualSeizedAssets, actualRepaidAssets) = morpho.liquidate(marketParams, borrower, seizedAssets, repaidShares, data);

        // Return unused loan tokens
        uint256 unusedAmount = estimatedRepayAmount - actualRepaidAssets;
        if (unusedAmount > 0) {
            IERC20(marketParams.loanToken).safeTransfer(msg.sender, unusedAmount);
        }

        // Calculate and collect protocol fee (50%)
        uint256 protocolFeeAmount = 0;
        if (config.protocolFee > 0) {
            uint256 totalBonus = actualSeizedAssets.mulDivDown(config.liquidationBonus, WAD + config.liquidationBonus);
            protocolFeeAmount = totalBonus.mulDivDown(config.protocolFee, WAD);
            accumulatedFees[marketId] += protocolFeeAmount;
            actualSeizedAssets -= protocolFeeAmount;
        }

        // Transfer collateral to liquidator
        if (actualSeizedAssets > 0) {
            IERC20(marketParams.collateralToken).safeTransfer(msg.sender, actualSeizedAssets);
        }

        // Update timestamp
        lastLiquidationTime[marketId][borrower] = block.timestamp;

        // Record liquidation
        if (config.whitelistEnabled) {
            whitelistRegistry.recordLiquidation(marketId, msg.sender);
        }

        emit LiquidationExecuted(
            marketId,
            msg.sender,
            borrower,
            actualSeizedAssets,
            actualRepaidAssets,
            healthFactor,
            config.liquidationBonus
        );

        return (actualSeizedAssets, actualRepaidAssets);
    }

    /// @notice Request liquidation (Step 1 of two-step)
    function requestLiquidation(
        MarketParams memory marketParams,
        address borrower,
        uint256 liquidationRatio
    ) external returns (uint256 seizedAssets, uint256 repaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];

        if (!config.enabled) revert MarketNotConfigured();
        if (liquidationRatio == 0 || liquidationRatio > config.maxLiquidationRatio) {
            revert InvalidLiquidationRatio();
        }
        if (liquidationStatus[marketId][borrower] != LiquidationStatus.None) {
            revert InvalidLiquidationStatus();
        }

        // Check whitelist
        if (config.whitelistEnabled && !whitelistRegistry.canLiquidate(marketId, msg.sender)) {
            revert Unauthorized();
        }

        // Get position
        Market memory marketData = morpho.market(marketId);
        Position memory pos = morpho.position(marketId, borrower);

        uint256 collateralPrice = _getValidatedPrice(marketId, marketParams);
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(
            marketData.totalBorrowAssets,
            marketData.totalBorrowShares
        );
        uint256 healthFactor = HealthFactorLib.calculateHealthFactor(
            pos.collateral,
            collateralPrice,
            borrowed,
            marketParams.lltv
        );

        if (healthFactor >= WAD) revert HealthyPosition();

        // Check cooldown
        if (config.cooldownPeriod > 0 && lastLiquidationTime[marketId][borrower] > 0) {
            if (block.timestamp < lastLiquidationTime[marketId][borrower] + config.cooldownPeriod) {
                revert CooldownNotElapsed();
            }
        }

        // Calculate amounts
        uint256 debtToRepay = borrowed.mulDivDown(liquidationRatio, WAD);
        uint256 liquidationIncentiveFactor = WAD + config.liquidationBonus;
        uint256 collateralValue = debtToRepay.mulDivUp(liquidationIncentiveFactor, WAD);
        uint256 totalSeizedAssets = collateralValue.mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        require(totalSeizedAssets <= pos.collateral, "Insufficient collateral");
        if (totalSeizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();

        // Protocol fee: 50% of bonus
        uint256 bonusAmount = totalSeizedAssets.mulDivDown(
            config.liquidationBonus,
            liquidationIncentiveFactor
        );
        uint256 protocolFee = bonusAmount.mulDivDown(config.protocolFee, WAD);

        // Pull loan tokens
        uint256 estimatedRepay = debtToRepay * 12 / 10;
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepay);

        // Approve Morpho
        (bool success,) = marketParams.loanToken.call(
            abi.encodeWithSignature("approve(address,uint256)", address(morpho), type(uint256).max)
        );
        require(success, "Approve failed");

        // Execute through Morpho
        (uint256 actualSeized, uint256 actualRepaid) = morpho.liquidate(
            marketParams,
            borrower,
            totalSeizedAssets,
            0,
            ""
        );

        // Return unused
        if (estimatedRepay > actualRepaid) {
            IERC20(marketParams.loanToken).safeTransfer(msg.sender, estimatedRepay - actualRepaid);
        }

        // Calculate actual protocol fee
        uint256 actualProtocolFee = actualSeized.mulDivDown(protocolFee, totalSeizedAssets);
        accumulatedFees[marketId] += actualProtocolFee;

        // Transfer liquidator's share
        uint256 liquidatorShare = actualSeized - actualProtocolFee;
        if (liquidatorShare > 0) {
            IERC20(marketParams.collateralToken).safeTransfer(msg.sender, liquidatorShare);
        }

        // Update state
        liquidationStatus[marketId][borrower] = LiquidationStatus.Pending;
        liquidatorAddress[marketId][borrower] = msg.sender;
        pendingSeizedCollateral[marketId][borrower] = liquidatorShare;
        lastLiquidationTime[marketId][borrower] = block.timestamp;

        if (config.whitelistEnabled) {
            whitelistRegistry.recordLiquidation(marketId, msg.sender);
        }

        emit LiquidationRequested(
            marketId,
            borrower,
            msg.sender,
            actualRepaid,
            liquidatorShare,
            actualProtocolFee,
            liquidationRatio
        );

        return (liquidatorShare, actualRepaid);
    }

    /// @notice Complete liquidation (Step 2)
    function completeLiquidation(MarketParams memory marketParams, address borrower) external {
        Id marketId = marketParams.id();

        if (liquidationStatus[marketId][borrower] != LiquidationStatus.Pending) {
            revert InvalidLiquidationStatus();
        }
        if (liquidatorAddress[marketId][borrower] != msg.sender) {
            revert NotLiquidator();
        }

        liquidationStatus[marketId][borrower] = LiquidationStatus.Completed;

        emit LiquidationCompleted(marketId, borrower, msg.sender);
    }


    /* VIEW FUNCTIONS */
    
    /// @notice Get health factor for a borrower
    function getHealthFactor(MarketParams memory marketParams, address borrower)
        external
        view
        returns (uint256)
    {
        Id marketId = marketParams.id();
        Market memory marketData = morpho.market(marketId);
        Position memory pos = morpho.position(marketId, borrower);
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(
            marketData.totalBorrowAssets,
            marketData.totalBorrowShares
        );
        return HealthFactorLib.calculateHealthFactor(
            pos.collateral,
            collateralPrice,
            borrowed,
            marketParams.lltv
        );
    }
        /* INTERNAL FUNCTIONS */

    /// @notice Get validated price with oracle protection
    function _getValidatedPrice(Id marketId, MarketParams memory marketParams)
        internal
        view
        returns (uint256)
    {
        // Use simple oracle price (can be enhanced with PriceOracleLib later)
        return IOracle(marketParams.oracle).price();
    }
}
