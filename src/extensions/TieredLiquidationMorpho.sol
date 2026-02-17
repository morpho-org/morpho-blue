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

/// @title TieredLiquidationMorpho
/// @notice Hybrid liquidation: public one-step + whitelist two-step on top of Morpho Blue
contract TieredLiquidationMorpho {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using MarketParamsLib for MarketParams;

    /* ── Errors ────────────────────────────────────────────── */

    error Unauthorized();
    error HealthyPosition();
    error InvalidLiquidationAmount();
    error ExceedsMaxLiquidation();
    error BelowMinimumSeized();
    error CooldownNotElapsed();
    error MarketNotConfigured();
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
    error InvalidLiquidationStatus();
    error NotLiquidator();

    /* ── Events ────────────────────────────────────────────── */

    event LiquidationExecuted(
        Id indexed marketId, address indexed liquidator, address indexed borrower,
        uint256 seizedAssets, uint256 repaidAssets, uint256 healthFactor
    );
    event LiquidationRequested(
        Id indexed marketId, address indexed borrower, address indexed liquidator,
        uint256 seizedAssets, uint256 repaidAssets, uint256 depositAmount, uint256 expiresAt
    );
    event LiquidationCompleted(
        Id indexed marketId, address indexed borrower, address indexed liquidator,
        uint256 seizedAssets, uint256 repaidAssets
    );
    event LiquidationRequestCancelled(Id indexed marketId, address indexed borrower, address indexed canceller, bool isExpired);
    event MarketConfigured(Id indexed marketId);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeeRecipientSet(address indexed newFeeRecipient);
    event RefundFailed(address indexed recipient, uint256 amount);
    event RefundClaimed(address indexed recipient, uint256 amount);

    /* ── Types ─────────────────────────────────────────────── */

    enum LiquidationStatus { None, Pending, Completed }

    struct MarketConfig {
        bool enabled;
        bool publicLiquidationEnabled;
        bool twoStepLiquidationEnabled;
        uint256 liquidationBonus;
        uint256 maxLiquidationRatio;
        uint256 cooldownPeriod;
        uint256 minSeizedAssets;
        uint256 protocolFee;
        uint256 lockDuration;
        uint256 requestDeposit;
    }

    struct LiquidationRequest {
        address liquidator;
        uint64 requestTimestamp;
        LiquidationStatus status;
        uint128 liquidationRatio;
        uint128 depositAmount;
    }

    /// @dev Internal struct to avoid stack-too-deep
    struct PositionData {
        uint256 collateralPrice;
        uint256 borrowed;
        uint256 healthFactor;
        uint256 liquidationIncentiveFactor;
    }

    /* ── Immutables & State ────────────────────────────────── */

    IMorpho public immutable MORPHO;
    WhitelistRegistry public immutable WHITELIST_REGISTRY;

    address public owner;
    address public feeRecipient;

    mapping(Id => MarketConfig) public marketConfigs;
    mapping(Id => mapping(address => uint256)) public lastLiquidationTime;
    mapping(Id => uint256) public accumulatedFees;
    mapping(Id => mapping(address => LiquidationRequest)) public liquidationRequests;
    mapping(address => uint256) public failedRefunds;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _morpho, address _whitelistRegistry) {
        MORPHO = IMorpho(_morpho);
        WHITELIST_REGISTRY = WhitelistRegistry(_whitelistRegistry);
        owner = msg.sender;
        feeRecipient = msg.sender;
    }

    /* ── Owner Functions ───────────────────────────────────── */

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert InvalidAddress();
        feeRecipient = newFeeRecipient;
        emit FeeRecipientSet(newFeeRecipient);
    }

    function withdrawProtocolFees(Id marketId, MarketParams calldata marketParams) external onlyOwner {
        require(Id.unwrap(marketParams.id()) == Id.unwrap(marketId), "params/id mismatch");
        uint256 fees = accumulatedFees[marketId];
        if (fees == 0) revert NoFeesToWithdraw();
        accumulatedFees[marketId] = 0;
        IERC20(marketParams.collateralToken).safeTransfer(feeRecipient, fees);
    }

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
        if (enabled && !publicLiquidationEnabled && !twoStepLiquidationEnabled) revert AtLeastOneModeRequired();
        if (twoStepLiquidationEnabled && lockDuration == 0) revert LockDurationRequired();

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
        emit MarketConfigured(marketId);
    }

    /* ── One-Step Liquidation ──────────────────────────────── */

    function liquidate(
        MarketParams calldata marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256 actualSeizedAssets, uint256 actualRepaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];
        if (!config.enabled) revert MarketNotConfigured();

        bool isWhitelisted = WHITELIST_REGISTRY.canLiquidate(marketId, msg.sender);
        if (!config.publicLiquidationEnabled && !isWhitelisted) revert PublicLiquidationNotEnabled();

        _enforceNoActiveLock(marketId, borrower, config.lockDuration);

        PositionData memory pd = _loadAndValidatePosition(marketParams, marketId, borrower, config);
        Position memory pos = MORPHO.position(marketId, borrower);

        (uint256 maxSeizable,) = HealthFactorLib.calculateLiquidationLimits(
            pos.collateral, pd.borrowed, config.maxLiquidationRatio
        );

        uint256 seizedAssetsToPass;
        uint256 repaidSharesToPass;
        uint256 estimatedRepay;

        if (seizedAssets > 0) {
            if (seizedAssets > maxSeizable) revert ExceedsMaxLiquidation();
            if (seizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();
            seizedAssetsToPass = seizedAssets;
            uint256 quoted = seizedAssets.mulDivUp(pd.collateralPrice, ORACLE_PRICE_SCALE);
            estimatedRepay = quoted.wDivUp(pd.liquidationIncentiveFactor) * 12 / 10;
        } else if (repaidShares > 0) {
            Market memory m = MORPHO.market(marketId);
            uint256 repaidAmt = repaidShares.toAssetsUp(m.totalBorrowAssets, m.totalBorrowShares);
            (, uint256 maxRepay) = HealthFactorLib.calculateLiquidationLimits(
                pos.collateral, pd.borrowed, config.maxLiquidationRatio
            );
            if (repaidAmt > maxRepay) revert ExceedsMaxLiquidation();
            seizedAssets = repaidAmt.wMulDown(pd.liquidationIncentiveFactor)
                .mulDivDown(ORACLE_PRICE_SCALE, pd.collateralPrice);
            if (seizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();
            repaidSharesToPass = repaidShares;
            estimatedRepay = repaidAmt * 12 / 10;
        } else {
            revert InvalidLiquidationAmount();
        }

        (actualSeizedAssets, actualRepaidAssets) = _executeMorphoLiquidation(
            marketParams, borrower, seizedAssetsToPass, repaidSharesToPass, estimatedRepay, data
        );

        actualSeizedAssets = _deductProtocolFee(marketId, actualSeizedAssets, config);
        if (actualSeizedAssets > 0) IERC20(marketParams.collateralToken).safeTransfer(msg.sender, actualSeizedAssets);

        lastLiquidationTime[marketId][borrower] = block.timestamp;
        if (isWhitelisted) WHITELIST_REGISTRY.recordLiquidation(marketId, msg.sender);

        emit LiquidationExecuted(marketId, msg.sender, borrower, actualSeizedAssets, actualRepaidAssets, pd.healthFactor);
    }

    /* ── Two-Step Liquidation ──────────────────────────────── */

    /// @notice Step 1: Request liquidation — locks rights with ETH deposit
    function requestLiquidation(
        MarketParams calldata marketParams,
        address borrower,
        uint256 liquidationRatio
    ) external payable returns (uint256 requestedSeizedAssets, uint256 requestedRepaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];
        if (!config.enabled) revert MarketNotConfigured();
        if (!config.twoStepLiquidationEnabled) revert TwoStepLiquidationNotEnabled();
        if (!WHITELIST_REGISTRY.canLiquidate(marketId, msg.sender)) revert Unauthorized();
        if (liquidationRatio == 0 || liquidationRatio > config.maxLiquidationRatio) revert InvalidLiquidationRatio();
        if (msg.value < config.requestDeposit) revert InsufficientDeposit();

        _enforceNoActiveLock(marketId, borrower, config.lockDuration);

        PositionData memory pd = _loadAndValidatePosition(marketParams, marketId, borrower, config);
        Position memory pos = MORPHO.position(marketId, borrower);

        uint256 debtToRepay = pd.borrowed.mulDivDown(liquidationRatio, WAD);
        uint256 collateralValue = debtToRepay.mulDivUp(pd.liquidationIncentiveFactor, WAD);
        requestedSeizedAssets = collateralValue.mulDivUp(ORACLE_PRICE_SCALE, pd.collateralPrice);
        if (requestedSeizedAssets > pos.collateral) revert InsufficientCollateral();
        if (requestedSeizedAssets < config.minSeizedAssets) revert BelowMinimumSeized();
        requestedRepaidAssets = debtToRepay;

        liquidationRequests[marketId][borrower] = LiquidationRequest({
            liquidator: msg.sender,
            requestTimestamp: uint64(block.timestamp),
            status: LiquidationStatus.Pending,
            liquidationRatio: uint128(liquidationRatio),
            depositAmount: uint128(msg.value)
        });

        uint256 expiresAt = block.timestamp + config.lockDuration;
        emit LiquidationRequested(marketId, borrower, msg.sender, requestedSeizedAssets, requestedRepaidAssets, msg.value, expiresAt);
    }

    /// @notice Step 2: Execute the locked liquidation
    function executeLiquidation(
        MarketParams calldata marketParams,
        address borrower,
        bytes calldata data
    ) external returns (uint256 actualSeizedAssets, uint256 actualRepaidAssets) {
        Id marketId = marketParams.id();
        MarketConfig memory config = marketConfigs[marketId];
        LiquidationRequest storage request = liquidationRequests[marketId][borrower];

        if (request.status != LiquidationStatus.Pending) revert InvalidLiquidationStatus();
        if (request.liquidator != msg.sender) revert NotLiquidator();
        if (!WHITELIST_REGISTRY.canLiquidate(marketId, msg.sender)) revert Unauthorized();

        uint256 expiresAt = uint256(request.requestTimestamp) + config.lockDuration;
        if (block.timestamp > expiresAt) revert LiquidationRequestExpired();

        uint256 storedRatio = uint256(request.liquidationRatio);
        uint256 depositToRefund = uint256(request.depositAmount);

        // Validate current position
        Market memory marketData = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);
        if (HealthFactorLib.calculateHealthFactor(pos.collateral, collateralPrice, borrowed, marketParams.lltv) >= WAD) {
            revert HealthyPosition();
        }

        uint256 lif = WAD + config.liquidationBonus;
        uint256 debtToRepay = borrowed.mulDivDown(storedRatio, WAD);
        uint256 totalSeized = debtToRepay.mulDivUp(lif, WAD).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
        if (totalSeized > pos.collateral) revert InsufficientCollateral();

        (actualSeizedAssets, actualRepaidAssets) = _executeMorphoLiquidation(
            marketParams, borrower, totalSeized, 0, debtToRepay * 12 / 10, data
        );

        uint256 liquidatorShare = _deductProtocolFee(marketId, actualSeizedAssets, config);
        if (liquidatorShare > 0) IERC20(marketParams.collateralToken).safeTransfer(msg.sender, liquidatorShare);

        request.status = LiquidationStatus.Completed;
        lastLiquidationTime[marketId][borrower] = block.timestamp;
        WHITELIST_REGISTRY.recordLiquidation(marketId, msg.sender);

        if (depositToRefund > 0) _safeTransferETH(msg.sender, depositToRefund);
        emit LiquidationCompleted(marketId, borrower, msg.sender, liquidatorShare, actualRepaidAssets);
    }

    /* ── Cancel / Claim ────────────────────────────────────── */

    function cancelLiquidationRequest(MarketParams calldata marketParams, address borrower) external {
        Id marketId = marketParams.id();
        LiquidationRequest storage request = liquidationRequests[marketId][borrower];
        if (request.status != LiquidationStatus.Pending) revert NoActiveRequest();

        uint256 expiresAt = uint256(request.requestTimestamp) + marketConfigs[marketId].lockDuration;
        bool isExpired = block.timestamp > expiresAt;
        if (!isExpired && msg.sender != request.liquidator) revert RequestNotExpired();

        address originalLiquidator = request.liquidator;
        uint256 depositToRefund = uint256(request.depositAmount);
        delete liquidationRequests[marketId][borrower];
        if (depositToRefund > 0) _safeTransferETH(originalLiquidator, depositToRefund);
        emit LiquidationRequestCancelled(marketId, borrower, msg.sender, isExpired);
    }

    function claimFailedRefund() external {
        uint256 amount = failedRefunds[msg.sender];
        if (amount == 0) revert NoFailedRefund();
        failedRefunds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert RefundClaimFailed();
        emit RefundClaimed(msg.sender, amount);
    }

    /* ── View Functions ────────────────────────────────────── */

    function getHealthFactor(MarketParams calldata marketParams, address borrower) external view returns (uint256) {
        Id marketId = marketParams.id();
        Market memory m = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);
        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(m.totalBorrowAssets, m.totalBorrowShares);
        return HealthFactorLib.calculateHealthFactor(pos.collateral, IOracle(marketParams.oracle).price(), borrowed, marketParams.lltv);
    }

    function getLiquidationRequest(Id marketId, address borrower) external view returns (
        address liquidator, uint256 requestTimestamp, uint256 liquidationRatio,
        uint256 depositAmount, LiquidationStatus status, uint256 expiresAt
    ) {
        LiquidationRequest storage r = liquidationRequests[marketId][borrower];
        return (r.liquidator, uint256(r.requestTimestamp), uint256(r.liquidationRatio),
                uint256(r.depositAmount), r.status, uint256(r.requestTimestamp) + marketConfigs[marketId].lockDuration);
    }

    /* ── Internal Helpers ──────────────────────────────────── */

    function _loadAndValidatePosition(
        MarketParams calldata marketParams, Id marketId, address borrower, MarketConfig memory config
    ) internal view returns (PositionData memory pd) {
        Market memory m = MORPHO.market(marketId);
        Position memory pos = MORPHO.position(marketId, borrower);
        pd.collateralPrice = IOracle(marketParams.oracle).price();
        pd.borrowed = uint256(pos.borrowShares).toAssetsUp(m.totalBorrowAssets, m.totalBorrowShares);
        pd.healthFactor = HealthFactorLib.calculateHealthFactor(pos.collateral, pd.collateralPrice, pd.borrowed, marketParams.lltv);
        if (pd.healthFactor >= WAD) revert HealthyPosition();
        uint256 lastTime = lastLiquidationTime[marketId][borrower];
        if (config.cooldownPeriod > 0 && lastTime > 0 && block.timestamp < lastTime + config.cooldownPeriod) {
            revert CooldownNotElapsed();
        }
        pd.liquidationIncentiveFactor = WAD + config.liquidationBonus;
    }

    function _enforceNoActiveLock(Id marketId, address borrower, uint256 lockDuration) internal {
        LiquidationRequest storage request = liquidationRequests[marketId][borrower];
        if (request.status == LiquidationStatus.Pending) {
            uint256 expiresAt = uint256(request.requestTimestamp) + lockDuration;
            if (block.timestamp < expiresAt) revert LiquidationRequestLocked();
            address orig = request.liquidator;
            uint256 deposit = uint256(request.depositAmount);
            delete liquidationRequests[marketId][borrower];
            if (deposit > 0) _safeTransferETH(orig, deposit);
            emit LiquidationRequestCancelled(marketId, borrower, msg.sender, true);
        }
    }

    function _executeMorphoLiquidation(
        MarketParams calldata marketParams, address borrower,
        uint256 seizedAssets, uint256 repaidShares, uint256 estimatedRepay, bytes calldata data
    ) internal returns (uint256 actualSeized, uint256 actualRepaid) {
        address loanToken = marketParams.loanToken;
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), estimatedRepay);

        // Approve only when needed (fixes V-06)
        (bool success,) = loanToken.call(
            abi.encodeWithSignature("approve(address,uint256)", address(MORPHO), type(uint256).max)
        );
        if (!success) revert ApproveFailed();

        (actualSeized, actualRepaid) = MORPHO.liquidate(marketParams, borrower, seizedAssets, repaidShares, data);

        if (estimatedRepay > actualRepaid) {
            IERC20(loanToken).safeTransfer(msg.sender, estimatedRepay - actualRepaid);
        }
    }

    /// @dev Checked arithmetic for fee subtraction (fixes V-03)
    function _deductProtocolFee(Id marketId, uint256 seizedAssets, MarketConfig memory config)
        internal returns (uint256)
    {
        if (config.protocolFee == 0) return seizedAssets;
        uint256 lif = WAD + config.liquidationBonus;
        uint256 totalBonus = seizedAssets.mulDivDown(config.liquidationBonus, lif);
        uint256 feeAmount = totalBonus.mulDivDown(config.protocolFee, WAD);
        require(feeAmount <= seizedAssets, "fee exceeds seized");
        accumulatedFees[marketId] += feeAmount;
        return seizedAssets - feeAmount;
    }

    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            failedRefunds[to] += amount;
            emit RefundFailed(to, amount);
        }
    }

    receive() external payable {}
}
