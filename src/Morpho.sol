// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./interfaces/IMorpho.sol";
import "./interfaces/IMorphoCallbacks.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IOracle} from "./interfaces/IOracle.sol";

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MarketLib, Market} from "./libraries/MarketLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib, WAD} from "./libraries/FixedPointMathLib.sol";

/// @dev The maximum fee a market can have (25%).
uint256 constant MAX_FEE = 25;
/// @dev Liquidation cursor.
uint256 constant LIQUIDATION_CURSOR = 0.3e18;
/// @dev Max liquidation incentive factor.
uint256 constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

/// @dev The EIP-712 typeHash for EIP712Domain.
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The EIP-712 typeHash for Authorization.
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");

/// @title Morpho
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice The Morpho contract.
contract Morpho is IMorpho {
    using MarketLib for Market;
    using MarketLib for MarketParams;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IMorpho
    bytes32 public immutable DOMAIN_SEPARATOR;

    /* INTERNAL STORAGE */

    mapping(Id => Market) internal _market;

    /* PUBLIC STORAGE */

    /// @inheritdoc IMorpho
    address public owner;
    /// @inheritdoc IMorpho
    address public feeRecipient;
    /// @inheritdoc IMorpho
    mapping(address => bool) public isIrmEnabled;
    /// @inheritdoc IMorpho
    mapping(uint256 => bool) public isLltvEnabled;
    /// @inheritdoc IMorpho
    mapping(address => mapping(address => bool)) public isAuthorized;
    /// @inheritdoc IMorpho
    mapping(address => uint256) public nonce;

    /* CONSTRUCTOR */

    /// @notice Initializes the contract.
    /// @param newOwner The new owner of the contract.
    constructor(address newOwner) {
        owner = newOwner;

        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Morpho"), block.chainid, address(this)));
    }

    /* MODIFIERS */

    /// @notice Reverts if the caller is not the owner.
    modifier onlyOwner() {
        require(msg.sender == owner, ErrorsLib.NOT_OWNER);
        _;
    }

    /* ONLY OWNER FUNCTIONS */

    /// @inheritdoc IMorpho
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;

        emit EventsLib.SetOwner(newOwner);
    }

    /// @inheritdoc IMorpho
    function enableIrm(address irm) external onlyOwner {
        isIrmEnabled[irm] = true;

        emit EventsLib.EnableIrm(address(irm));
    }

    /// @inheritdoc IMorpho
    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, ErrorsLib.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;

        emit EventsLib.EnableLltv(lltv);
    }

    /// @inheritdoc IMorpho
    function setFee(MarketParams memory marketParams, uint256 newFee) external onlyOwner {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, ErrorsLib.MAX_FEE_EXCEEDED);

        // Accrue interests using the previous fee set before changing it.
        _accrueInterests(marketParams, id);

        market.setFee(newFee);

        emit EventsLib.SetFee(id, newFee);
    }

    /// @inheritdoc IMorpho
    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit EventsLib.SetFeeRecipient(recipient);
    }

    /* MARKET CREATION */

    /// @inheritdoc IMorpho
    function createMarket(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(isIrmEnabled[marketParams.irm], ErrorsLib.IRM_NOT_ENABLED);
        require(isLltvEnabled[marketParams.lltv], ErrorsLib.LLTV_NOT_ENABLED);
        require(market.lastUpdate() == 0, ErrorsLib.MARKET_CREATED);

        market.setLastUpdate(block.timestamp);

        emit EventsLib.CreateMarket(id, marketParams);
    }

    /* SUPPLY MANAGEMENT */

    /// @inheritdoc IMorpho
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256) {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(marketParams, id);

        if (assets > 0) shares = assets.toSharesDown(market.totalSupply(), market.totalSupplyShares());
        else assets = shares.toAssetsUp(market.totalSupply(), market.totalSupplyShares());

        market.increaseSupplyShares(onBehalf, shares);
        market.increaseTotalSupplyShares(shares);
        market.increaseTotalSupply(assets);

        emit EventsLib.Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoSupplyCallback(msg.sender).onMorphoSupply(assets, data);

        IERC20(marketParams.borrowableToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /// @inheritdoc IMorpho
    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        if (assets > 0) shares = assets.toSharesUp(market.totalSupply(), market.totalSupplyShares());
        else assets = shares.toAssetsDown(market.totalSupply(), market.totalSupplyShares());

        market.decreaseSupplyShares(onBehalf, shares);
        market.decreaseTotalSupplyShares(shares);
        market.decreaseTotalSupply(assets);

        emit EventsLib.Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);

        require(market.totalBorrow() <= market.totalSupply(), ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(marketParams.borrowableToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /* BORROW MANAGEMENT */

    /// @inheritdoc IMorpho
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        if (assets > 0) shares = assets.toSharesUp(market.totalBorrow(), market.totalBorrowShares());
        else assets = shares.toAssetsDown(market.totalBorrow(), market.totalBorrowShares());

        market.increaseBorrowShares(onBehalf, shares);
        market.increaseTotalBorrowShares(shares);
        market.increaseTotalBorrow(assets);

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(market.totalBorrow() <= market.totalSupply(), ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(marketParams.borrowableToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /// @inheritdoc IMorpho
    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256) {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(marketParams, id);

        if (assets > 0) shares = assets.toSharesDown(market.totalBorrow(), market.totalBorrowShares());
        else assets = shares.toAssetsUp(market.totalBorrow(), market.totalBorrowShares());

        market.decreaseBorrowShares(onBehalf, shares);
        market.decreaseTotalBorrowShares(shares);
        market.decreaseTotalBorrow(assets);

        emit EventsLib.Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoRepayCallback(msg.sender).onMorphoRepay(assets, data);

        IERC20(marketParams.borrowableToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /* COLLATERAL MANAGEMENT */

    /// @inheritdoc IMorpho
    function supplyCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, bytes calldata data)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        // Don't accrue interests because it's not required and it saves gas.

        market.increaseCollateral(onBehalf, assets);

        emit EventsLib.SupplyCollateral(id, msg.sender, onBehalf, assets);

        if (data.length > 0) IMorphoSupplyCollateralCallback(msg.sender).onMorphoSupplyCollateral(assets, data);

        IERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @inheritdoc IMorpho
    function withdrawCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, address receiver)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        market.decreaseCollateral(onBehalf, assets);

        emit EventsLib.WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);

        IERC20(marketParams.collateralToken).safeTransfer(receiver, assets);
    }

    /* LIQUIDATION */

    /// @inheritdoc IMorpho
    function liquidate(MarketParams memory marketParams, address borrower, uint256 seized, bytes calldata data)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(seized != 0, ErrorsLib.ZERO_ASSETS);

        _accrueInterests(marketParams, id);

        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        require(!_isHealthy(marketParams, id, borrower, collateralPrice, priceScale), ErrorsLib.HEALTHY_POSITION);

        uint256 repaid =
            seized.mulDivUp(collateralPrice, priceScale).wDivUp(liquidationIncentiveFactor(marketParams.lltv));
        uint256 repaidShares = repaid.toSharesDown(market.totalBorrow(), market.totalBorrowShares());

        market.decreaseBorrowShares(borrower, repaidShares);
        market.decreaseTotalBorrowShares(repaidShares);
        market.decreaseTotalBorrow(repaid);

        market.decreaseCollateral(borrower, seized);

        // Realize the bad debt if needed.
        uint256 badDebtShares;
        if (market.collateral(borrower) == 0) {
            badDebtShares = market.borrowShares(borrower);
            uint256 badDebt = badDebtShares.toAssetsUp(market.totalBorrow(), market.totalBorrowShares());
            market.decreaseTotalSupply(badDebt);
            market.decreaseTotalBorrow(badDebt);
            market.decreaseTotalBorrowShares(badDebtShares);
            market.setBorrowShares(borrower, 0);
        }

        IERC20(marketParams.collateralToken).safeTransfer(msg.sender, seized);

        emit EventsLib.Liquidate(id, msg.sender, borrower, repaid, repaidShares, seized, badDebtShares);

        if (data.length > 0) IMorphoLiquidateCallback(msg.sender).onMorphoLiquidate(repaid, data);

        IERC20(marketParams.borrowableToken).safeTransferFrom(msg.sender, address(this), repaid);
    }

    /* FLASH LOANS */

    /// @inheritdoc IFlashLender
    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        IERC20(token).safeTransfer(msg.sender, assets);

        emit EventsLib.FlashLoan(msg.sender, token, assets);

        IMorphoFlashLoanCallback(msg.sender).onMorphoFlashLoan(assets, data);

        IERC20(token).safeTransferFrom(msg.sender, address(this), assets);
    }

    /* AUTHORIZATION */

    /// @inheritdoc IMorpho
    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;

        emit EventsLib.SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized);
    }

    /// @inheritdoc IMorpho
    /// @dev The signature is malleable, but it has no impact on the security here.
    function setAuthorizationWithSig(
        address authorizer,
        address authorized,
        bool newIsAuthorized,
        uint256 deadline,
        Signature calldata signature
    ) external {
        require(block.timestamp < deadline, ErrorsLib.SIGNATURE_EXPIRED);

        uint256 usedNonce = nonce[authorizer]++;
        bytes32 hashStruct =
            keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorizer, authorized, newIsAuthorized, usedNonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && authorizer == signatory, ErrorsLib.INVALID_SIGNATURE);

        emit EventsLib.IncrementNonce(msg.sender, authorizer, usedNonce);

        isAuthorized[authorizer][authorized] = newIsAuthorized;

        emit EventsLib.SetAuthorization(msg.sender, authorizer, authorized, newIsAuthorized);
    }

    function _isSenderAuthorized(address user) internal view returns (bool) {
        return msg.sender == user || isAuthorized[user][msg.sender];
    }

    /* INTEREST MANAGEMENT */

    /// @inheritdoc IMorpho
    function accrueInterests(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        require(_market[id].lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);

        _accrueInterests(marketParams, id);
    }

    /// @dev Accrues interests for `marketParams`.
    function _accrueInterests(MarketParams memory marketParams, Id id) internal {
        Market storage market = _market[id];

        uint256 elapsed = block.timestamp - market.lastUpdate();

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = market.totalBorrow();

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRate(marketParams);
            uint256 accruedInterests = marketTotalBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            market.increaseTotalBorrow(accruedInterests);
            market.increaseTotalSupply(accruedInterests);

            uint256 feeShares;
            if (market.fee() != 0) {
                uint256 feeAmount = accruedInterests * market.fee() / 100;
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares = feeAmount.mulDivDown(market.totalSupplyShares(), market.totalSupply() - feeAmount);
                market.increaseSupplyShares(feeRecipient, feeShares);
                market.increaseTotalSupplyShares(feeShares);
            }

            emit EventsLib.AccrueInterests(id, borrowRate, accruedInterests, feeShares);
        }

        market.setLastUpdate(block.timestamp);
    }

    /* HEALTH CHECK */

    /// @notice Returns whether the position of `user` in the given `marketParams` is healthy.
    function _isHealthy(MarketParams memory marketParams, Id id, address user) internal view returns (bool) {
        Market storage market = _market[id];

        if (market.borrowShares(user) == 0) return true;

        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        return _isHealthy(marketParams, id, user, collateralPrice, priceScale);
    }

    /// @notice Returns whether the position of `user` in the given `marketParams` with the given `collateralPrice` and `priceScale` is healthy.
    function _isHealthy(
        MarketParams memory marketParams,
        Id id,
        address user,
        uint256 collateralPrice,
        uint256 priceScale
    ) internal view returns (bool) {
        Market storage market = _market[id];

        uint256 borrowed = market.borrowShares(user).toAssetsUp(market.totalBorrow(), market.totalBorrowShares());
        uint256 maxBorrow = market.collateral(user).mulDivDown(collateralPrice, priceScale).wMulDown(marketParams.lltv);

        return maxBorrow >= borrowed;
    }

    /* STORAGE VIEW */

    /// @inheritdoc IMorpho
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory res) {
        uint256 nSlots = slots.length;

        res = new bytes32[](nSlots);

        for (uint256 i; i < nSlots;) {
            bytes32 slot = slots[i++];

            /// @solidity memory-safe-assembly
            assembly {
                mstore(add(res, mul(i, 32)), sload(slot))
            }
        }
    }

    function totalSupplyShares(Id id) external view returns (uint256) {
        return _market[id].totalSupplyShares();
    }

    function totalBorrowShares(Id id) external view returns (uint256) {
        return _market[id].totalBorrowShares();
    }

    function supplyShares(Id id, address user) external view returns (uint256) {
        return _market[id].supplyShares(user);
    }

    function borrowShares(Id id, address user) external view returns (uint256) {
        return _market[id].borrowShares(user);
    }

    function totalSupply(Id id) external view returns (uint256) {
        return _market[id].totalSupply();
    }

    function totalBorrow(Id id) external view returns (uint256) {
        return _market[id].totalBorrow();
    }

    function lastUpdate(Id id) external view returns (uint256) {
        return _market[id].lastUpdate();
    }

    function fee(Id id) external view returns (uint256) {
        return _market[id].fee();
    }

    function collateral(Id id, address user) external view returns (uint256) {
        return _market[id].collateral(user);
    }

    /* LIQUIDATION INCENTIVE FACTOR */

    /// @dev The liquidation incentive factor is min(maxIncentiveFactor, 1/(1 - cursor(1 - lltv))).
    function liquidationIncentiveFactor(uint256 lltv) private pure returns (uint256) {
        return
            UtilsLib.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
    }
}
