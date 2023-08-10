// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./interfaces/IBlue.sol";
import "./interfaces/IBlueCallbacks.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IOracle} from "./interfaces/IOracle.sol";

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MarketLib, Market, UserBalances, MarketState} from "./libraries/MarketLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib, WAD} from "./libraries/FixedPointMathLib.sol";

/// @dev The maximum fee a market can have (25%).
uint256 constant MAX_FEE = 25;
/// @dev The alpha parameter used to compute the incentive during a liquidation.
uint256 constant ALPHA = 0.5e18;

/// @dev The EIP-712 typeHash for EIP712Domain.
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The EIP-712 typeHash for Authorization.
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");

/// @title Blue
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice The Blue contract.
contract Blue is IBlue {
    using MarketLib for Market;
    using MarketLib for MarketParams;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IBlue
    bytes32 public immutable DOMAIN_SEPARATOR;

    /* INTERNAL STORAGE */

    // Markets.
    mapping(Id => Market) internal _market;

    /* PUBLIC STORAGE */

    /// @inheritdoc IBlue
    address public owner;
    /// @inheritdoc IBlue
    address public feeRecipient;
    /// @inheritdoc IBlue
    mapping(address => bool) public isIrmEnabled;
    /// @inheritdoc IBlue
    mapping(uint256 => bool) public isLltvEnabled;
    /// @inheritdoc IBlue
    mapping(address => mapping(address => bool)) public isAuthorized;
    /// @inheritdoc IBlue
    mapping(address => uint256) public nonce;

    /* CONSTRUCTOR */

    /// @notice Initializes the contract.
    /// @param newOwner The new owner of the contract.
    constructor(address newOwner) {
        owner = newOwner;

        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Blue"), block.chainid, address(this)));
    }

    /* MODIFIERS */

    /// @notice Reverts if the caller is not the owner.
    modifier onlyOwner() {
        require(msg.sender == owner, ErrorsLib.NOT_OWNER);
        _;
    }

    /* ONLY OWNER FUNCTIONS */

    /// @inheritdoc IBlue
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;

        emit EventsLib.SetOwner(newOwner);
    }

    /// @inheritdoc IBlue
    function enableIrm(address irm) external onlyOwner {
        isIrmEnabled[irm] = true;

        emit EventsLib.EnableIrm(address(irm));
    }

    /// @inheritdoc IBlue
    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, ErrorsLib.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;

        emit EventsLib.EnableLltv(lltv);
    }

    /// @inheritdoc IBlue
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

    /// @inheritdoc IBlue
    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit EventsLib.SetFeeRecipient(recipient);
    }

    /* MARKET CREATION */

    /// @inheritdoc IBlue
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

    /// @inheritdoc IBlue
    function supply(
        MarketParams memory marketParams,
        uint256 amount,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(amount, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(marketParams, id);

        if (amount > 0) shares = amount.toSharesDown(market.totalSupply(), market.totalSupplyShares());
        else amount = shares.toAssetsUp(market.totalSupply(), market.totalSupplyShares());

        market.increaseSupplyShares(onBehalf, shares);
        market.increaseTotalSupplyShares(shares);
        market.increaseTotalSupply(amount);

        emit EventsLib.Supply(id, msg.sender, onBehalf, amount, shares);

        if (data.length > 0) IBlueSupplyCallback(msg.sender).onBlueSupply(amount, data);

        IERC20(marketParams.borrowableAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IBlue
    function withdraw(
        MarketParams memory marketParams,
        uint256 amount,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(amount, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        if (amount > 0) shares = amount.toSharesUp(market.totalSupply(), market.totalSupplyShares());
        else amount = shares.toAssetsDown(market.totalSupply(), market.totalSupplyShares());

        market.decreaseSupplyShares(onBehalf, shares);
        market.decreaseTotalSupplyShares(shares);
        market.decreaseTotalSupply(amount);

        emit EventsLib.Withdraw(id, msg.sender, onBehalf, receiver, amount, shares);

        require(market.totalBorrow() <= market.totalSupply(), ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(marketParams.borrowableAsset).safeTransfer(receiver, amount);
    }

    /* BORROW MANAGEMENT */

    /// @inheritdoc IBlue
    function borrow(
        MarketParams memory marketParams,
        uint256 amount,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(amount, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        if (amount > 0) shares = amount.toSharesUp(market.totalBorrow(), market.totalBorrowShares());
        else amount = shares.toAssetsDown(market.totalBorrow(), market.totalBorrowShares());

        market.increaseBorrowShares(onBehalf, shares);
        market.increaseTotalBorrowShares(shares);
        market.increaseTotalBorrow(amount);

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, amount, shares);

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(market.totalBorrow() <= market.totalSupply(), ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(marketParams.borrowableAsset).safeTransfer(receiver, amount);
    }

    /// @inheritdoc IBlue
    function repay(
        MarketParams memory marketParams,
        uint256 amount,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(amount, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(marketParams, id);

        if (amount > 0) shares = amount.toSharesDown(market.totalBorrow(), market.totalBorrowShares());
        else amount = shares.toAssetsUp(market.totalBorrow(), market.totalBorrowShares());

        market.decreaseBorrowShares(onBehalf, shares);
        market.decreaseTotalBorrowShares(shares);
        market.decreaseTotalBorrow(amount);

        emit EventsLib.Repay(id, msg.sender, onBehalf, amount, shares);

        if (data.length > 0) IBlueRepayCallback(msg.sender).onBlueRepay(amount, data);

        IERC20(marketParams.borrowableAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    /* COLLATERAL MANAGEMENT */

    /// @inheritdoc IBlue
    function supplyCollateral(MarketParams memory marketParams, uint256 amount, address onBehalf, bytes calldata data)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(amount != 0, ErrorsLib.ZERO_AMOUNT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        // Don't accrue interests because it's not required and it saves gas.

        market.increaseCollateral(onBehalf, amount);

        emit EventsLib.SupplyCollateral(id, msg.sender, onBehalf, amount);

        if (data.length > 0) IBlueSupplyCollateralCallback(msg.sender).onBlueSupplyCollateral(amount, data);

        IERC20(marketParams.collateralAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IBlue
    function withdrawCollateral(MarketParams memory marketParams, uint256 amount, address onBehalf, address receiver)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(amount != 0, ErrorsLib.ZERO_AMOUNT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        market.decreaseCollateral(onBehalf, amount);

        emit EventsLib.WithdrawCollateral(id, msg.sender, onBehalf, receiver, amount);

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);

        IERC20(marketParams.collateralAsset).safeTransfer(receiver, amount);
    }

    /* LIQUIDATION */

    /// @inheritdoc IBlue
    function liquidate(MarketParams memory marketParams, address borrower, uint256 seized, bytes calldata data)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(seized != 0, ErrorsLib.ZERO_AMOUNT);

        _accrueInterests(marketParams, id);

        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        require(!_isHealthy(marketParams, id, borrower, collateralPrice, priceScale), ErrorsLib.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.wMulDown(WAD.wDivDown(marketParams.lltv) - WAD);
        uint256 repaid = seized.mulDivUp(collateralPrice, priceScale).wDivUp(incentive);
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

        IERC20(marketParams.collateralAsset).safeTransfer(msg.sender, seized);

        emit EventsLib.Liquidate(id, msg.sender, borrower, repaid, repaidShares, seized, badDebtShares);

        if (data.length > 0) IBlueLiquidateCallback(msg.sender).onBlueLiquidate(repaid, data);

        IERC20(marketParams.borrowableAsset).safeTransferFrom(msg.sender, address(this), repaid);
    }

    /* FLASH LOANS */

    /// @inheritdoc IFlashLender
    function flashLoan(address token, uint256 amount, bytes calldata data) external {
        IERC20(token).safeTransfer(msg.sender, amount);

        emit EventsLib.FlashLoan(msg.sender, token, amount);

        IBlueFlashLoanCallback(msg.sender).onBlueFlashLoan(amount, data);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /* AUTHORIZATION */

    /// @inheritdoc IBlue
    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;

        emit EventsLib.SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized);
    }

    /// @inheritdoc IBlue
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

    /// @inheritdoc IBlue
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
}
