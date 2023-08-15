// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Id, IMorpho, Market, MktState, Authorization, Signature} from "./interfaces/IMorpho.sol";
import {IFlashLender} from "./interfaces/IFlashLender.sol";
import {
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback,
    IMorphoFlashLoanCallback
} from "./interfaces/IMorphoCallbacks.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IOracle} from "./interfaces/IOracle.sol";

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MathLib, WAD} from "./libraries/MathLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

/// @dev The maximum fee a market can have (25%).
uint256 constant MAX_FEE = 0.25e18;
/// @dev Oracle price scale.
uint256 constant ORACLE_PRICE_SCALE = 1e36;
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
    using MathLib for uint256;
    using MarketLib for Market;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using {UtilsLib.toUint128} for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IMorpho
    bytes32 public immutable DOMAIN_SEPARATOR;

    /* STORAGE */

    /// @inheritdoc IMorpho
    address public owner;
    /// @inheritdoc IMorpho
    address public feeRecipient;
    /// @inheritdoc IMorpho
    mapping(Id => mapping(address => uint256)) public supplyShares;
    /// @inheritdoc IMorpho
    mapping(Id => mapping(address => uint256)) public borrowShares;
    /// @inheritdoc IMorpho
    mapping(Id => mapping(address => uint256)) public collateral;
    /// See mktState.
    mapping(Id => MktState) internal _mktState;
    /// @inheritdoc IMorpho
    mapping(address => bool) public isIrmEnabled;
    /// @inheritdoc IMorpho
    mapping(uint256 => bool) public isLltvEnabled;
    /// @inheritdoc IMorpho
    mapping(address => mapping(address => bool)) public isAuthorized;
    /// @inheritdoc IMorpho
    mapping(address => uint256) public nonce;
    /// @inheritdoc IMorpho
    mapping(Id => Market) public idToMarket;

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
    function setFee(Market memory market, uint256 newFee) external onlyOwner {
        Id id = market.id();
        require(_mktState[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, ErrorsLib.MAX_FEE_EXCEEDED);

        // Accrue interests using the previous fee set before changing it.
        _accrueInterests(market, id);

        // Ok unsafe cast.
        _mktState[id].fee = uint128(newFee);

        emit EventsLib.SetFee(id, newFee);
    }

    /// @inheritdoc IMorpho
    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit EventsLib.SetFeeRecipient(recipient);
    }

    /* MARKET CREATION */

    /// @inheritdoc IMorpho
    function createMarket(Market memory market) external {
        Id id = market.id();
        require(isIrmEnabled[market.irm], ErrorsLib.IRM_NOT_ENABLED);
        require(isLltvEnabled[market.lltv], ErrorsLib.LLTV_NOT_ENABLED);
        require(_mktState[id].lastUpdate == 0, ErrorsLib.MARKET_CREATED);

        // Ok unsafe cast.
        _mktState[id].lastUpdate = uint128(block.timestamp);
        idToMarket[id] = market;

        emit EventsLib.CreateMarket(id, market);
    }

    /* SUPPLY MANAGEMENT */

    /// @inheritdoc IMorpho
    function supply(Market memory market, uint256 assets, uint256 shares, address onBehalf, bytes calldata data)
        external
        returns (uint256, uint256)
    {
        Id id = market.id();
        MktState storage mktStatePtr = _mktState[id];
        require(mktStatePtr.lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesDown(mktStatePtr.totalSupply, mktStatePtr.totalSupplyShares);
        else assets = shares.toAssetsUp(mktStatePtr.totalSupply, mktStatePtr.totalSupplyShares);

        supplyShares[id][onBehalf] += shares;
        mktStatePtr.totalSupplyShares += shares.toUint128();
        mktStatePtr.totalSupply += assets.toUint128();

        emit EventsLib.Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoSupplyCallback(msg.sender).onMorphoSupply(assets, data);

        IERC20(market.borrowableToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /// @inheritdoc IMorpho
    function withdraw(Market memory market, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256)
    {
        Id id = market.id();
        MktState storage mktStatePtr = _mktState[id];
        require(mktStatePtr.lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesUp(mktStatePtr.totalSupply, mktStatePtr.totalSupplyShares);
        else assets = shares.toAssetsDown(mktStatePtr.totalSupply, mktStatePtr.totalSupplyShares);

        supplyShares[id][onBehalf] -= shares;
        mktStatePtr.totalSupplyShares -= shares.toUint128();
        mktStatePtr.totalSupply -= assets.toUint128();

        emit EventsLib.Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);

        require(mktStatePtr.totalBorrow <= mktStatePtr.totalSupply, ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(market.borrowableToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /* BORROW MANAGEMENT */

    /// @inheritdoc IMorpho
    function borrow(Market memory market, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256)
    {
        Id id = market.id();
        MktState storage mktStatePtr = _mktState[id];
        require(mktStatePtr.lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesUp(mktStatePtr.totalBorrow, mktStatePtr.totalBorrowShares);
        else assets = shares.toAssetsDown(mktStatePtr.totalBorrow, mktStatePtr.totalBorrowShares);

        borrowShares[id][onBehalf] += shares;
        mktStatePtr.totalBorrowShares += shares.toUint128();
        mktStatePtr.totalBorrow += assets.toUint128();

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        require(_isHealthy(market, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(mktStatePtr.totalBorrow <= mktStatePtr.totalSupply, ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(market.borrowableToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /// @inheritdoc IMorpho
    function repay(Market memory market, uint256 assets, uint256 shares, address onBehalf, bytes calldata data)
        external
        returns (uint256, uint256)
    {
        Id id = market.id();
        MktState storage mktStatePtr = _mktState[id];
        require(mktStatePtr.lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(market, id);

        if (assets > 0) shares = assets.toSharesDown(mktStatePtr.totalBorrow, mktStatePtr.totalBorrowShares);
        else assets = shares.toAssetsUp(mktStatePtr.totalBorrow, mktStatePtr.totalBorrowShares);

        borrowShares[id][onBehalf] -= shares;
        mktStatePtr.totalBorrowShares -= shares.toUint128();
        mktStatePtr.totalBorrow -= assets.toUint128();

        emit EventsLib.Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoRepayCallback(msg.sender).onMorphoRepay(assets, data);

        IERC20(market.borrowableToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /* COLLATERAL MANAGEMENT */

    /// @inheritdoc IMorpho
    function supplyCollateral(Market memory market, uint256 assets, address onBehalf, bytes calldata data) external {
        Id id = market.id();
        require(_mktState[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][onBehalf] += assets;

        emit EventsLib.SupplyCollateral(id, msg.sender, onBehalf, assets);

        if (data.length > 0) IMorphoSupplyCollateralCallback(msg.sender).onMorphoSupplyCollateral(assets, data);

        IERC20(market.collateralToken).safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @inheritdoc IMorpho
    function withdrawCollateral(Market memory market, uint256 assets, address onBehalf, address receiver) external {
        Id id = market.id();
        require(_mktState[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(market, id);

        collateral[id][onBehalf] -= assets;

        emit EventsLib.WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);

        require(_isHealthy(market, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);

        IERC20(market.collateralToken).safeTransfer(receiver, assets);
    }

    /* LIQUIDATION */

    /// @inheritdoc IMorpho
    function liquidate(Market memory market, address borrower, uint256 seized, bytes calldata data)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        Id id = market.id();
        MktState storage mktStatePtr = _mktState[id];
        require(mktStatePtr.lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(seized != 0, ErrorsLib.ZERO_ASSETS);

        _accrueInterests(market, id);

        uint256 collateralPrice = IOracle(market.oracle).price();

        require(!_isHealthy(market, id, borrower, collateralPrice), ErrorsLib.HEALTHY_POSITION);

        assetsRepaid =
            seized.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(liquidationIncentiveFactor(market.lltv));
        sharesRepaid = assetsRepaid.toSharesDown(mktStatePtr.totalBorrow, mktStatePtr.totalBorrowShares);

        borrowShares[id][borrower] -= sharesRepaid;
        mktStatePtr.totalBorrowShares -= sharesRepaid.toUint128();
        mktStatePtr.totalBorrow -= assetsRepaid.toUint128();

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        uint256 badDebtShares;
        if (collateral[id][borrower] == 0) {
            badDebtShares = borrowShares[id][borrower];
            uint256 badDebt = badDebtShares.toAssetsUp(mktStatePtr.totalBorrow, mktStatePtr.totalBorrowShares);
            mktStatePtr.totalSupply -= badDebt.toUint128();
            mktStatePtr.totalBorrow -= badDebt.toUint128();
            mktStatePtr.totalBorrowShares -= badDebtShares.toUint128();
            borrowShares[id][borrower] = 0;
        }

        IERC20(market.collateralToken).safeTransfer(msg.sender, seized);

        emit EventsLib.Liquidate(id, msg.sender, borrower, assetsRepaid, sharesRepaid, seized, badDebtShares);

        if (data.length > 0) IMorphoLiquidateCallback(msg.sender).onMorphoLiquidate(assetsRepaid, data);

        IERC20(market.borrowableToken).safeTransferFrom(msg.sender, address(this), assetsRepaid);
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
    /// @dev Warning: reverts if the signature has already been submitted.
    /// @dev The signature is malleable, but it has no impact on the security here.
    function setAuthorizationWithSig(Authorization memory authorization, Signature calldata signature) external {
        require(block.timestamp < authorization.deadline, ErrorsLib.SIGNATURE_EXPIRED);
        require(authorization.nonce == nonce[authorization.authorizer]++, ErrorsLib.INVALID_NONCE);

        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && authorization.authorizer == signatory, ErrorsLib.INVALID_SIGNATURE);

        emit EventsLib.IncrementNonce(msg.sender, authorization.authorizer, authorization.nonce);

        isAuthorized[authorization.authorizer][authorization.authorized] = authorization.isAuthorized;

        emit EventsLib.SetAuthorization(
            msg.sender, authorization.authorizer, authorization.authorized, authorization.isAuthorized
        );
    }

    function _isSenderAuthorized(address user) internal view returns (bool) {
        return msg.sender == user || isAuthorized[user][msg.sender];
    }

    /* INTEREST MANAGEMENT */

    /// @inheritdoc IMorpho
    function accrueInterests(Market memory market) external {
        Id id = market.id();
        require(_mktState[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);

        _accrueInterests(market, id);
    }

    /// @dev Accrues interests for `market`.
    function _accrueInterests(Market memory market, Id id) internal {
        uint256 elapsed = block.timestamp - _mktState[id].lastUpdate;

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = _mktState[id].totalBorrow;

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            _mktState[id].totalBorrow += accruedInterests.toUint128();
            _mktState[id].totalSupply += accruedInterests.toUint128();

            uint256 feeShares;
            if (_mktState[id].fee != 0) {
                uint256 feeAmount = accruedInterests.wMulDown(_mktState[id].fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares =
                    feeAmount.toSharesDown(_mktState[id].totalSupply - feeAmount, _mktState[id].totalSupplyShares);
                supplyShares[id][feeRecipient] += feeShares;
                // Ok unsafe cast.
                _mktState[id].totalSupplyShares += uint128(feeShares);
            }

            emit EventsLib.AccrueInterests(id, borrowRate, accruedInterests, feeShares);
        }

        // Ok unsafe cast.
        _mktState[id].lastUpdate = uint128(block.timestamp);
    }

    /* HEALTH CHECK */

    /// @notice Returns whether the position of `user` in the given `market` is healthy.
    function _isHealthy(Market memory market, Id id, address user) internal view returns (bool) {
        if (borrowShares[id][user] == 0) return true;

        uint256 collateralPrice = IOracle(market.oracle).price();

        return _isHealthy(market, id, user, collateralPrice);
    }

    /// @notice Returns whether the position of `user` in the given `market` with the given `collateralPrice` and `priceScale` is healthy.
    function _isHealthy(Market memory market, Id id, address user, uint256 collateralPrice)
        internal
        view
        returns (bool)
    {
        uint256 borrowed = borrowShares[id][user].toAssetsUp(_mktState[id].totalBorrow, _mktState[id].totalBorrowShares);
        uint256 maxBorrow = collateral[id][user].mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);

        return maxBorrow >= borrowed;
    }

    /* STORAGE VIEW */

    /// @inheritdoc IMorpho
    function mktState(Id id) external view returns (MktState memory) {
        return _mktState[id];
    }

    /// @inheritdoc IMorpho
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory res) {
        uint256 nSlots = slots.length;

        res = new bytes32[](nSlots);

        for (uint256 i; i < nSlots;) {
            bytes32 slot = slots[i++];

            assembly ("memory-safe") {
                mstore(add(res, mul(i, 32)), sload(slot))
            }
        }
    }

    /* LIQUIDATION INCENTIVE FACTOR */

    /// @dev The liquidation incentive factor is min(maxIncentiveFactor, 1/(1 - cursor(1 - lltv))).
    function liquidationIncentiveFactor(uint256 lltv) private pure returns (uint256) {
        return
            UtilsLib.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
    }
}
