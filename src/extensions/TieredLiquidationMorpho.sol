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
/// @dev Implements hybrid liquidation mode: public one-step + whitelist two-step
/// @dev Gas optimized version
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
    error PublicLiquidationNotEnabled();
    error TwoStepLiquidationNotEnabled();
    error LiquidationRequestLocked();
    error LiquidationRequestExpired();
    error InsufficientDeposit();
    error RequestNotExpired();
    error NoActiveRequest();
    error InvalidAddress();
    error NoFeesToWithdraw();
    error NoFailedRefund();
    error ApproveFailed();
    error RefundClaimFailed();
    error InsufficientCollateral();
    error AtLeastOneModeRequired();
    error LockDurationRequired();
    error BonusTooHigh();
    error RatioExceeds100();
    error ProtocolFeeTooHigh();

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
        uint256 requestedSeizedAssets,
        uint256 requestedRepaidAssets,
        uint256 depositAmount,
        uint256 expiresAt
    );

    event LiquidationCompleted(
        Id indexed marketId,
        address indexed borrower,
        address indexed liquidator,
        uint256 seizedAssets,
        uint256 repaidAssets
    );

    event LiquidationRequestCancelled(
        Id indexed marketId,
        address indexed borrower,
        address indexed canceller,
        bool isExpired
    );

    event MarketConfigured(
        Id indexed marketId,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio,
        uint256 cooldownPeriod,
        uint256 minSeizedAssets,
        bool publicLiquidationEnabled,
        bool twoStepLiquidationEnabled,
        uint256 lockDuration,
        uint256 protocolFee
    );

    event RefundFailed(address indexed recipient, uint256 amount);
    event RefundClaimed(address indexed recipient, uint256 amount);

    /* STORAGE */

    /// @notice Liquidation status enum (uses uint8 internally)
    enum LiquidationStatus { None, Pending, Completed }

    /// @notice Market configuration with hybrid mode support
    /// @dev Packed for gas optimization: bools grouped together
    struct MarketConfig {
        // Slot 1: packed bools (3 bytes) + padding
        bool enabled;
        bool publicLiquidationEnabled;
        bool twoStepLiquidationEnabled;
        // Slot 2-7: uint256 values (each takes full slot)
        uint256 liquidationBonus;
        uint256 maxLiquidationRatio;
        uint256 cooldownPeriod;
        uint256 minSeizedAssets;
        uint256 protocolFee;
        uint256 lockDuration;
        uint256 requestDeposit;
    }

    /// @notice Two-step liquidation request data
    /// @dev Packed for gas optimization
    struct LiquidationRequest {
        address liquidator;              // 20 bytes
        uint64 requestTimestamp;         // 8 bytes - sufficient until year 584942
        LiquidationStatus status;        // 1 byte
        // New slot
        uint128 liquidationRatio;        // 16 bytes - sufficient for WAD precision
        uint128 depositAmount;           // 16 bytes - sufficient for ETH amounts
    }

    /// @notice The underlying Morpho protocol
    IMorpho public immutable MORPHO;

    /// @notice The whitelist registry
    WhitelistRegistry public immutable WHITELIST_REGISTRY;

    /// @notice Owner of the contract
    address public owner;

    /// @notice Protocol fee recipient
    address public feeRecipient;

    /// @notice Market ID => Liquidation configuration
    mapping(Id => MarketConfig) public marketConfigs;

    /// @notice Market ID => Borrower => Last liquidation timestamp
    mapping(Id => mapping(address => uint256)) public lastLiquidationTime;

    /// @notice Market ID => Accumulated protocol fees
    mapping(Id => uint256) public accumulatedFees;

    /// @notice Two-step liquidation tracking: Market ID => Borrower => Request
    mapping(Id => mapping(address => LiquidationRequest)) public liquidationRequests;

    /// @notice Failed refunds that can be claimed later
    mapping(address => uint256) public failedRefunds;

    /* MODIFIERS */

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /* CONSTRUCTOR */

    constructor(address _morpho, address _whitelistRegistry) {
        MORPHO = IMorpho(_morpho);
        WHITELIST_REGISTRY = WhitelistRegistry(_whitelistRegistry);
        owner = msg.sender;
        feeRecipient = msg.sender;
    }

    /* OWNER FUNCTIONS */

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Set fee recipient
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert InvalidAddress();
        feeRecipient = newFeeRecipient;
    }

    /// @notice Withdraw accumulated protocol fees
    function withdrawProtocolFees(Id marketId, MarketParams calldata marketParams) external onlyOwner {
        uint256 fees = accumulatedFees[marketId];
        if (fees == 0) revert NoFeesToWithdraw();
        
        accumulatedFees[marketId] = 0;
        IERC20(marketParams.collateralToken).safeTransfer(feeRecipient, fees);
    }

    /// @notice Configure market liquidation parameters with hybrid mode support
    function configureMarket(
        Id marketId,
        bool enabled,
        uint256 liquidationBonus,
        uint256 maxLiquidationRatio,
        uint256 cooldownPeriod,
        uint256 minSeizedAssets,
        bool publicLiquidationEnabled,
        bool twoStepLiquidationEnabled,
        uint256 lockDuration,
        uint256 requestDeposit,
        uint256 protocolFee
    ) external onlyOwner {
        if (liquidationBonus > 0.2e18) revert BonusTooHigh();
        if (maxLiquidationRatio > WAD) revert RatioExceeds100();
        if (protocolFee > WAD) revert ProtocolFeeTooHigh();
        
        if (enabled) {
            if (!publicLiquidationEnabled && !twoStepLiquidationEnabled) revert AtLeastOneModeRequired();
        }
        
        if (twoStepLiquidationEnabled) {
            if (lockDuration == 0) revert LockDurationRequired();
        }

        marketConfigs[marketId] = MarketConfig({
            enabled: enabled,
            publicLiquidationEnabled: publicLiquidationEnabled,
            twoStepLiquidationEnabled: twoStepLiquidationEnabled,
            liquidationBonus: liquidationBonus,
            maxLiquidationRatio: maxLiquidationRatio,
            cooldownPeriod: cooldownPeriod,
            minSeizedAssets: minSeizedAssets,
            protocolFee: protocolFee,
            lockDuration: lockDuration,
            requestDeposit: requestDeposit
        });

        emit MarketConfigured(
            marketId,
            liquidationBonus,
            maxLiquidationRatio,
            cooldownPeriod,
            minSeizedAssets,
            publicLiquidationEnabled,
            twoStepLiquidationEnabled,
            lockDuration,
            protocolFee
        );
    }

    /* ONE-STEP LIQUIDATION (PUBLIC OR WHITELIST) */

    /// @notice Standard one-step liquidation
    function liquidate(
        MarketParams calldata marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256 actualSeizedAssets, uint256 actualRepaidAssets) {
        Id marketId = marketParams.id();
        
        // Cache config in memory to avoid multiple SLOADs
        MarketConfig memory config = marketConfigs[marketId];

        if (!config.enabled) revert MarketNotConfigured();

        // Permission check
        bool isWhitelisted = WHITELIST_REGISTRY.canLiquidate(marketId, msg.sender);
        
        if (!config.publicLiquidationEnabled && !isWhitelisted) {
            revert PublicLiquidationNotEnabled();
        }

        // Check two-step request lock
        {
            LiquidationRequest storage request = liquidationRequests[marketId][borrower];
            if (request.status == LiquidationStatus.Pending) {
                uint256 expiresAt;
                unchecked {
                    expiresAt = uint256(request.requestTimestamp) + config.lockDuration;
                }
                if (block.timestamp < expiresAt) {
                    revert LiquidationRequestLocked();
                }
                _clearExpiredRequest(marketId, borrower, request);
            }
        }

        // Get position data
        Market memory marketData = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);

        // Calculate health factor
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
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
        {
            uint256 lastTime = lastLiquidationTime[marketId][borrower];
            if (config.cooldownPeriod > 0 && lastTime > 0) {
                unchecked {
                    if (block.timestamp < lastTime + config.cooldownPeriod) {
                        revert CooldownNotElapsed();
                    }
                }
            }
        }

        // Calculate liquidation limits
        (uint256 maxSeizableCollateral, uint256 maxRepayableDebt) =
            HealthFactorLib.calculateLiquidationLimits(pos.collateral, borrowed, config.maxLiquidationRatio);

        uint256 liquidationIncentiveFactor;
        unchecked {
            liquidationIncentiveFactor = WAD + config.liquidationBonus;
        }

        uint256 seizedAssetsToPass;
        uint256 repaidSharesToPass;
        uint256 estimatedRepayAmount;

        if (seizedAssets > 0) {
            if (seizedAssets > maxSeizableCollateral) revert ExceedsMaxLiquidation();
            if (seizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();

            seizedAssetsToPass = seizedAssets;
            uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
            unchecked {
                estimatedRepayAmount = (seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor) * 12) / 10;
            }
        } else if (repaidShares > 0) {
            uint256 repaidAmount = repaidShares.toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);
            if (repaidAmount > maxRepayableDebt) revert ExceedsMaxLiquidation();

            seizedAssets = repaidAmount.wMulDown(liquidationIncentiveFactor).mulDivDown(
                ORACLE_PRICE_SCALE,
                collateralPrice
            );

            if (seizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();

            repaidSharesToPass = repaidShares;
            unchecked {
                estimatedRepayAmount = (repaidAmount * 12) / 10;
            }
        } else {
            revert InvalidLiquidationAmount();
        }

        // Pull and approve loan tokens
        address loanToken = marketParams.loanToken;
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepayAmount);
        _approveToken(loanToken, address(MORPHO));

        // Execute liquidation
        (actualSeizedAssets, actualRepaidAssets) = MORPHO.liquidate(
            marketParams, borrower, seizedAssetsToPass, repaidSharesToPass, data
        );

        // Return unused loan tokens
        unchecked {
            uint256 unusedAmount = estimatedRepayAmount - actualRepaidAssets;
            if (unusedAmount > 0) {
                IERC20(loanToken).safeTransfer(msg.sender, unusedAmount);
            }
        }

        // Calculate and collect protocol fee
        if (config.protocolFee > 0) {
            uint256 totalBonus = actualSeizedAssets.mulDivDown(config.liquidationBonus, liquidationIncentiveFactor);
            uint256 protocolFeeAmount = totalBonus.mulDivDown(config.protocolFee, WAD);
            accumulatedFees[marketId] += protocolFeeAmount;
            unchecked {
                actualSeizedAssets -= protocolFeeAmount;
            }
        }

        // Transfer collateral to liquidator
        if (actualSeizedAssets > 0) {
            IERC20(marketParams.collateralToken).safeTransfer(msg.sender, actualSeizedAssets);
        }

        // Update timestamp
        lastLiquidationTime[marketId][borrower] = block.timestamp;

        // Record liquidation if whitelisted
        if (isWhitelisted) {
            WHITELIST_REGISTRY.recordLiquidation(marketId, msg.sender);
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
    }

    /* TWO-STEP LIQUIDATION (WHITELIST ONLY) */

    /// @notice Request liquidation (Step 1) - locks liquidation rights
    function requestLiquidation(
        MarketParams calldata marketParams,
        address borrower,
        uint256 liquidationRatio
    ) external payable returns (uint256 requestedSeizedAssets, uint256 requestedRepaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];

        if (!config.enabled) revert MarketNotConfigured();
        if (!config.twoStepLiquidationEnabled) revert TwoStepLiquidationNotEnabled();
        
        if (!WHITELIST_REGISTRY.canLiquidate(marketId, msg.sender)) {
            revert Unauthorized();
        }

        if (liquidationRatio == 0 || liquidationRatio > config.maxLiquidationRatio) {
            revert InvalidLiquidationRatio();
        }

        if (msg.value < config.requestDeposit) {
            revert InsufficientDeposit();
        }

        // Check existing request
        LiquidationRequest storage existingRequest = liquidationRequests[marketId][borrower];
        if (existingRequest.status == LiquidationStatus.Pending) {
            uint256 requestExpiresAt;
            unchecked {
                requestExpiresAt = uint256(existingRequest.requestTimestamp) + config.lockDuration;
            }
            if (block.timestamp < requestExpiresAt) {
                revert LiquidationRequestLocked();
            }
            _clearExpiredRequest(marketId, borrower, existingRequest);
        }

        // Get position and validate health
        Market memory marketData = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
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
        {
            uint256 lastTime = lastLiquidationTime[marketId][borrower];
            if (config.cooldownPeriod > 0 && lastTime > 0) {
                unchecked {
                    if (block.timestamp < lastTime + config.cooldownPeriod) {
                        revert CooldownNotElapsed();
                    }
                }
            }
        }

        // Calculate expected amounts
        uint256 debtToRepay = borrowed.mulDivDown(liquidationRatio, WAD);
        uint256 liquidationIncentiveFactor;
        unchecked {
            liquidationIncentiveFactor = WAD + config.liquidationBonus;
        }
        uint256 collateralValue = debtToRepay.mulDivUp(liquidationIncentiveFactor, WAD);
        requestedSeizedAssets = collateralValue.mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        if (requestedSeizedAssets > pos.collateral) revert InsufficientCollateral();
        if (requestedSeizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();

        requestedRepaidAssets = debtToRepay;

        // Store request with packed struct
        liquidationRequests[marketId][borrower] = LiquidationRequest({
            liquidator: msg.sender,
            requestTimestamp: uint64(block.timestamp),
            status: LiquidationStatus.Pending,
            liquidationRatio: uint128(liquidationRatio),
            depositAmount: uint128(msg.value)
        });

        uint256 expiresAt;
        unchecked {
            expiresAt = block.timestamp + config.lockDuration;
        }

        emit LiquidationRequested(
            marketId,
            borrower,
            msg.sender,
            requestedSeizedAssets,
            requestedRepaidAssets,
            msg.value,
            expiresAt
        );
    }

    /// @notice Execute liquidation (Step 2) - performs actual liquidation
    function executeLiquidation(
        MarketParams calldata marketParams,
        address borrower,
        bytes calldata data
    ) external returns (uint256 actualSeizedAssets, uint256 actualRepaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];
        
        LiquidationRequest storage request = liquidationRequests[marketId][borrower];

        if (request.status != LiquidationStatus.Pending) {
            revert InvalidLiquidationStatus();
        }
        if (request.liquidator != msg.sender) {
            revert NotLiquidator();
        }

        // Check time window
        uint256 expiresAt;
        unchecked {
            expiresAt = uint256(request.requestTimestamp) + config.lockDuration;
        }
        if (block.timestamp > expiresAt) {
            revert LiquidationRequestExpired();
        }

        // Cache request data before modifications
        uint256 storedLiquidationRatio = uint256(request.liquidationRatio);
        uint256 depositToRefund = uint256(request.depositAmount);

        // Get current position data
        Market memory marketData = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
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

        // Calculate amounts
        uint256 debtToRepay = borrowed.mulDivDown(storedLiquidationRatio, WAD);
        uint256 liquidationIncentiveFactor;
        unchecked {
            liquidationIncentiveFactor = WAD + config.liquidationBonus;
        }
        uint256 collateralValue = debtToRepay.mulDivUp(liquidationIncentiveFactor, WAD);
        uint256 totalSeizedAssets = collateralValue.mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);

        if (totalSeizedAssets > pos.collateral) revert InsufficientCollateral();

        // Pull and approve loan tokens
        uint256 estimatedRepay;
        unchecked {
            estimatedRepay = (debtToRepay * 12) / 10;
        }
        address loanToken = marketParams.loanToken;
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepay);
        _approveToken(loanToken, address(MORPHO));

        // Execute through Morpho
        (actualSeizedAssets, actualRepaidAssets) = MORPHO.liquidate(
            marketParams,
            borrower,
            totalSeizedAssets,
            0,
            data
        );

        // Return unused loan tokens
        unchecked {
            if (estimatedRepay > actualRepaidAssets) {
                IERC20(loanToken).safeTransfer(msg.sender, estimatedRepay - actualRepaidAssets);
            }
        }

        // Calculate protocol fee
        uint256 liquidatorShare = actualSeizedAssets;
        if (config.protocolFee > 0) {
            uint256 totalBonus = actualSeizedAssets.mulDivDown(config.liquidationBonus, liquidationIncentiveFactor);
            uint256 protocolFeeAmount = totalBonus.mulDivDown(config.protocolFee, WAD);
            accumulatedFees[marketId] += protocolFeeAmount;
            unchecked {
                liquidatorShare = actualSeizedAssets - protocolFeeAmount;
            }
        }

        // Transfer collateral
        if (liquidatorShare > 0) {
            IERC20(marketParams.collateralToken).safeTransfer(msg.sender, liquidatorShare);
        }

        // Update state
        request.status = LiquidationStatus.Completed;
        lastLiquidationTime[marketId][borrower] = block.timestamp;

        // Record liquidation
        WHITELIST_REGISTRY.recordLiquidation(marketId, msg.sender);

        // Refund deposit
        if (depositToRefund > 0) {
            _safeTransferETH(msg.sender, depositToRefund);
        }

        emit LiquidationCompleted(
            marketId,
            borrower,
            msg.sender,
            liquidatorShare,
            actualRepaidAssets
        );
    }

    /// @notice Cancel a liquidation request
    function cancelLiquidationRequest(
        MarketParams calldata marketParams,
        address borrower
    ) external {
        Id marketId = marketParams.id();
        LiquidationRequest storage request = liquidationRequests[marketId][borrower];

        if (request.status != LiquidationStatus.Pending) {
            revert NoActiveRequest();
        }

        MarketConfig memory config = marketConfigs[marketId];
        uint256 expiresAt;
        unchecked {
            expiresAt = uint256(request.requestTimestamp) + config.lockDuration;
        }
        bool isExpired = block.timestamp > expiresAt;

        if (!isExpired && msg.sender != request.liquidator) {
            revert RequestNotExpired();
        }

        address originalLiquidator = request.liquidator;
        uint256 depositToRefund = uint256(request.depositAmount);

        // Clear request
        delete liquidationRequests[marketId][borrower];

        // Refund deposit
        if (depositToRefund > 0) {
            _safeTransferETH(originalLiquidator, depositToRefund);
        }

        emit LiquidationRequestCancelled(marketId, borrower, msg.sender, isExpired);
    }

    /// @notice Claim failed refunds
    function claimFailedRefund() external {
        uint256 amount = failedRefunds[msg.sender];
        if (amount == 0) revert NoFailedRefund();
        
        failedRefunds[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert RefundClaimFailed();
        
        emit RefundClaimed(msg.sender, amount);
    }

    /* VIEW FUNCTIONS */
    
    /// @notice Get health factor for a borrower
    function getHealthFactor(MarketParams calldata marketParams, address borrower)
        external
        view
        returns (uint256)
    {
        Id marketId = marketParams.id();
        Market memory marketData = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);
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

    /// @notice Get liquidation request details
    function getLiquidationRequest(Id marketId, address borrower)
        external
        view
        returns (
            address liquidator,
            uint256 requestTimestamp,
            uint256 liquidationRatio,
            uint256 depositAmount,
            LiquidationStatus status,
            uint256 expiresAt
        )
    {
        LiquidationRequest storage request = liquidationRequests[marketId][borrower];
        MarketConfig storage config = marketConfigs[marketId];
        
        unchecked {
            expiresAt = uint256(request.requestTimestamp) + config.lockDuration;
        }
        
        return (
            request.liquidator,
            uint256(request.requestTimestamp),
            uint256(request.liquidationRatio),
            uint256(request.depositAmount),
            request.status,
            expiresAt
        );
    }

    /// @notice Check if a position can be liquidated via one-step
    function canLiquidateOneStep(Id marketId, address liquidator) external view returns (bool) {
        MarketConfig storage config = marketConfigs[marketId];
        if (!config.enabled) return false;
        if (config.publicLiquidationEnabled) return true;
        return WHITELIST_REGISTRY.canLiquidate(marketId, liquidator);
    }

    /// @notice Check if a position can be liquidated via two-step
    function canLiquidateTwoStep(Id marketId, address liquidator) external view returns (bool) {
        MarketConfig storage config = marketConfigs[marketId];
        if (!config.enabled) return false;
        if (!config.twoStepLiquidationEnabled) return false;
        return WHITELIST_REGISTRY.canLiquidate(marketId, liquidator);
    }

    /* INTERNAL FUNCTIONS */

    /// @notice Approve token spending (max approval, only if needed)
    function _approveToken(address token, address spender) internal {
        // Use low-level call to handle non-standard ERC20
        (bool success,) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, type(uint256).max)
        );
        if (!success) revert ApproveFailed();
    }

    /// @notice Safe ETH transfer with failed refund storage
    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            failedRefunds[to] += amount;
            emit RefundFailed(to, amount);
        }
    }

    /// @notice Clear an expired liquidation request
    function _clearExpiredRequest(Id marketId, address borrower, LiquidationRequest storage request) internal {
        if (request.status != LiquidationStatus.Pending) return;

        address originalLiquidator = request.liquidator;
        uint256 depositToRefund = uint256(request.depositAmount);

        // Clear request
        delete liquidationRequests[marketId][borrower];

        // Refund deposit
        if (depositToRefund > 0) {
            _safeTransferETH(originalLiquidator, depositToRefund);
        }

        emit LiquidationRequestCancelled(marketId, borrower, msg.sender, true);
    }

    /// @notice Receive ETH for deposits
    receive() external payable {}
}
