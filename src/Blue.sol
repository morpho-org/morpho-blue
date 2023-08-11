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
import {MarketLib} from "./libraries/MarketLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib, WAD} from "./libraries/FixedPointMathLib.sol";

/// @dev The maximum fee a market can have (25%).
uint256 constant MAX_FEE = 0.25e18;
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
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IBlue
    bytes32 public immutable DOMAIN_SEPARATOR;

    /* STORAGE */

    /// @inheritdoc IBlue
    address public owner;
    /// @inheritdoc IBlue
    address public feeRecipient;
    /// @inheritdoc IBlue
    mapping(Id => mapping(address => uint256)) public supplyShares;
    /// @inheritdoc IBlue
    mapping(Id => mapping(address => uint256)) public borrowShares;
    /// @inheritdoc IBlue
    mapping(Id => mapping(address => uint256)) public collateral;
    /// @inheritdoc IBlue
    mapping(Id => uint256) public totalSupply;
    /// @inheritdoc IBlue
    mapping(Id => uint256) public totalSupplyShares;
    /// @inheritdoc IBlue
    mapping(Id => uint256) public totalBorrow;
    /// @inheritdoc IBlue
    mapping(Id => uint256) public totalBorrowShares;
    /// @inheritdoc IBlue
    mapping(Id => uint256) public lastUpdate;
    /// @inheritdoc IBlue
    mapping(Id => uint256) public fee;
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
    function setFee(Market memory market, uint256 newFee) external onlyOwner {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, ErrorsLib.MAX_FEE_EXCEEDED);

        // Accrue interests using the previous fee set before changing it.
        _accrueInterests(market, id);

        fee[id] = newFee;

        emit EventsLib.SetFee(id, newFee);
    }

    /// @inheritdoc IBlue
    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit EventsLib.SetFeeRecipient(recipient);
    }

    /* MARKET CREATION */

    /// @inheritdoc IBlue
    function createMarket(Market memory market) external {
        Id id = market.id();
        require(isIrmEnabled[market.irm], ErrorsLib.IRM_NOT_ENABLED);
        require(isLltvEnabled[market.lltv], ErrorsLib.LLTV_NOT_ENABLED);
        require(lastUpdate[id] == 0, ErrorsLib.MARKET_CREATED);

        lastUpdate[id] = block.timestamp;

        emit EventsLib.CreateMarket(id, market);
    }

    /* SUPPLY MANAGEMENT */

    /// @inheritdoc IBlue
    function supply(Market memory market, uint256 assets, uint256 shares, address onBehalf, bytes calldata data)
        external
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesDown(totalSupply[id], totalSupplyShares[id]);
        else assets = shares.toAssetsUp(totalSupply[id], totalSupplyShares[id]);

        supplyShares[id][onBehalf] += shares;
        totalSupplyShares[id] += shares;
        totalSupply[id] += assets;

        emit EventsLib.Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IBlueSupplyCallback(msg.sender).onBlueSupply(assets, data);

        IERC20(market.borrowableAsset).safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @inheritdoc IBlue
    function withdraw(Market memory market, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesUp(totalSupply[id], totalSupplyShares[id]);
        else assets = shares.toAssetsDown(totalSupply[id], totalSupplyShares[id]);

        supplyShares[id][onBehalf] -= shares;
        totalSupplyShares[id] -= shares;
        totalSupply[id] -= assets;

        emit EventsLib.Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);

        require(totalBorrow[id] <= totalSupply[id], ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(market.borrowableAsset).safeTransfer(receiver, assets);
    }

    /* BORROW MANAGEMENT */

    /// @inheritdoc IBlue
    function borrow(Market memory market, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesUp(totalBorrow[id], totalBorrowShares[id]);
        else assets = shares.toAssetsDown(totalBorrow[id], totalBorrowShares[id]);

        borrowShares[id][onBehalf] += shares;
        totalBorrowShares[id] += shares;
        totalBorrow[id] += assets;

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        require(_isHealthy(market, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(totalBorrow[id] <= totalSupply[id], ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(market.borrowableAsset).safeTransfer(receiver, assets);
    }

    /// @inheritdoc IBlue
    function repay(Market memory market, uint256 assets, uint256 shares, address onBehalf, bytes calldata data)
        external
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesDown(totalBorrow[id], totalBorrowShares[id]);
        else assets = shares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]);

        borrowShares[id][onBehalf] -= shares;
        totalBorrowShares[id] -= shares;
        totalBorrow[id] -= assets;

        emit EventsLib.Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IBlueRepayCallback(msg.sender).onBlueRepay(assets, data);

        IERC20(market.borrowableAsset).safeTransferFrom(msg.sender, address(this), assets);
    }

    /* COLLATERAL MANAGEMENT */

    /// @inheritdoc IBlue
    function supplyCollateral(Market memory market, uint256 assets, address onBehalf, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_AMOUNT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][onBehalf] += assets;

        emit EventsLib.SupplyCollateral(id, msg.sender, onBehalf, assets);

        if (data.length > 0) IBlueSupplyCollateralCallback(msg.sender).onBlueSupplyCollateral(assets, data);

        IERC20(market.collateralAsset).safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @inheritdoc IBlue
    function withdrawCollateral(Market memory market, uint256 assets, address onBehalf, address receiver) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_AMOUNT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(market, id);

        collateral[id][onBehalf] -= assets;

        emit EventsLib.WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);

        require(_isHealthy(market, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);

        IERC20(market.collateralAsset).safeTransfer(receiver, assets);
    }

    /* LIQUIDATION */

    /// @inheritdoc IBlue
    function liquidate(Market memory market, address borrower, uint256 seized, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(seized != 0, ErrorsLib.ZERO_AMOUNT);

        _accrueInterests(market, id);

        (uint256 collateralPrice, uint256 priceScale) = IOracle(market.oracle).price();

        require(!_isHealthy(market, id, borrower, collateralPrice, priceScale), ErrorsLib.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.wMulDown(WAD.wDivDown(market.lltv) - WAD);
        uint256 repaid = seized.mulDivUp(collateralPrice, priceScale).wDivUp(incentive);
        uint256 repaidShares = repaid.toSharesDown(totalBorrow[id], totalBorrowShares[id]);

        borrowShares[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        uint256 badDebtShares;
        if (collateral[id][borrower] == 0) {
            badDebtShares = borrowShares[id][borrower];
            uint256 badDebt = badDebtShares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]);
            totalSupply[id] -= badDebt;
            totalBorrow[id] -= badDebt;
            totalBorrowShares[id] -= badDebtShares;
            borrowShares[id][borrower] = 0;
        }

        IERC20(market.collateralAsset).safeTransfer(msg.sender, seized);

        emit EventsLib.Liquidate(id, msg.sender, borrower, repaid, repaidShares, seized, badDebtShares);

        if (data.length > 0) IBlueLiquidateCallback(msg.sender).onBlueLiquidate(repaid, data);

        IERC20(market.borrowableAsset).safeTransferFrom(msg.sender, address(this), repaid);
    }

    /* FLASH LOANS */

    /// @inheritdoc IFlashLender
    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        IERC20(token).safeTransfer(msg.sender, assets);

        emit EventsLib.FlashLoan(msg.sender, token, assets);

        IBlueFlashLoanCallback(msg.sender).onBlueFlashLoan(assets, data);

        IERC20(token).safeTransferFrom(msg.sender, address(this), assets);
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

    /// @dev Accrues interests for `market`.
    function _accrueInterests(Market memory market, Id id) internal {
        uint256 elapsed = block.timestamp - lastUpdate[id];

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
            totalSupply[id] += accruedInterests;

            uint256 feeShares;
            if (fee[id] != 0) {
                uint256 feeAmount = accruedInterests.wMulDown(fee[id]);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares = feeAmount.mulDivDown(totalSupplyShares[id], totalSupply[id] - feeAmount);
                supplyShares[id][feeRecipient] += feeShares;
                totalSupplyShares[id] += feeShares;
            }

            emit EventsLib.AccrueInterests(id, borrowRate, accruedInterests, feeShares);
        }

        lastUpdate[id] = block.timestamp;
    }

    /* HEALTH CHECK */

    /// @notice Returns whether the position of `user` in the given `market` is healthy.
    function _isHealthy(Market memory market, Id id, address user) internal view returns (bool) {
        if (borrowShares[id][user] == 0) return true;

        (uint256 collateralPrice, uint256 priceScale) = IOracle(market.oracle).price();

        return _isHealthy(market, id, user, collateralPrice, priceScale);
    }

    /// @notice Returns whether the position of `user` in the given `market` with the given `collateralPrice` and `priceScale` is healthy.
    function _isHealthy(Market memory market, Id id, address user, uint256 collateralPrice, uint256 priceScale)
        internal
        view
        returns (bool)
    {
        uint256 borrowed = borrowShares[id][user].toAssetsUp(totalBorrow[id], totalBorrowShares[id]);
        uint256 maxBorrow = collateral[id][user].mulDivDown(collateralPrice, priceScale).wMulDown(market.lltv);

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
}
