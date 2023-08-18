// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Id, IMorpho, Info, User, Market, Authorization, Signature} from "./interfaces/IMorpho.sol";
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
    using MarketLib for Info;
    using UtilsLib for uint256;
    using SharesMathLib for uint256;
    using SharesMathLib for uint128;
    using SafeTransferLib for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMorpho
    bytes32 public immutable DOMAIN_SEPARATOR;

    /* STORAGE */

    /// @inheritdoc IMorpho
    address public owner;
    /// @inheritdoc IMorpho
    address public feeRecipient;
    /// @inheritdoc IMorpho
    mapping(Id => mapping(address => User)) public user;
    /// @inheritdoc IMorpho
    mapping(Id => Market) public market;
    /// @inheritdoc IMorpho
    mapping(address => bool) public isIrmEnabled;
    /// @inheritdoc IMorpho
    mapping(uint256 => bool) public isLltvEnabled;
    /// @inheritdoc IMorpho
    mapping(address => mapping(address => bool)) public isAuthorized;
    /// @inheritdoc IMorpho
    mapping(address => uint256) public nonce;
    /// @inheritdoc IMorpho
    mapping(Id => Info) public idToMarket;

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
    function setFee(Info memory info, uint256 newFee) external onlyOwner {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, ErrorsLib.MAX_FEE_EXCEEDED);

        // Accrue interest using the previous fee set before changing it.
        _accrueInterest(info, id);

        market[id].fee = uint128(newFee);

        emit EventsLib.SetFee(id, newFee);
    }

    /// @inheritdoc IMorpho
    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit EventsLib.SetFeeRecipient(recipient);
    }

    /* MARKET CREATION */

    /// @inheritdoc IMorpho
    function createMarket(Info memory info) external {
        Id id = info.id();
        require(isIrmEnabled[info.irm], ErrorsLib.IRM_NOT_ENABLED);
        require(isLltvEnabled[info.lltv], ErrorsLib.LLTV_NOT_ENABLED);
        require(market[id].lastUpdate == 0, ErrorsLib.MARKET_ALREADY_CREATED);

        market[id].lastUpdate = uint128(block.timestamp);
        idToMarket[id] = info;

        emit EventsLib.CreateMarket(id, info);
    }

    /* SUPPLY MANAGEMENT */

    /// @inheritdoc IMorpho
    function supply(Info memory info, uint128 assets, uint128 shares, address onBehalf, bytes calldata data)
        external
        returns (uint256, uint256)
    {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterest(info, id);

        if (assets > 0) {
            shares = assets.toSharesDown(market[id].totalSupplyAssets, market[id].totalSupplyShares).toUint128();
        } else {
            assets = shares.toAssetsUp(market[id].totalSupplyAssets, market[id].totalSupplyShares).toUint128();
        }

        user[id][onBehalf].supplyShares += shares;
        market[id].totalSupplyShares += shares;
        market[id].totalSupplyAssets += assets;

        emit EventsLib.Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoSupplyCallback(msg.sender).onMorphoSupply(assets, data);

        IERC20(info.borrowableToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /// @inheritdoc IMorpho
    function withdraw(Info memory info, uint128 assets, uint128 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256)
    {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest(info, id);

        if (assets > 0) {
            shares = assets.toSharesUp(market[id].totalSupplyAssets, market[id].totalSupplyShares).toUint128();
        } else {
            assets = shares.toAssetsDown(market[id].totalSupplyAssets, market[id].totalSupplyShares).toUint128();
        }

        user[id][onBehalf].supplyShares -= shares;
        market[id].totalSupplyShares -= shares;
        market[id].totalSupplyAssets -= assets;

        emit EventsLib.Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);

        require(market[id].totalBorrowAssets <= market[id].totalSupplyAssets, ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(info.borrowableToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /* BORROW MANAGEMENT */

    /// @inheritdoc IMorpho
    function borrow(Info memory info, uint128 assets, uint128 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256)
    {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest(info, id);

        if (assets > 0) {
            shares = assets.toSharesUp(market[id].totalBorrowAssets, market[id].totalBorrowShares).toUint128();
        } else {
            assets = shares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares).toUint128();
        }

        user[id][onBehalf].borrowShares += shares;
        market[id].totalBorrowShares += shares;
        market[id].totalBorrowAssets += assets;

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        require(_isHealthy(info, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(market[id].totalBorrowAssets <= market[id].totalSupplyAssets, ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(info.borrowableToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    /// @inheritdoc IMorpho
    function repay(Info memory info, uint128 assets, uint128 shares, address onBehalf, bytes calldata data)
        external
        returns (uint256, uint256)
    {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterest(info, id);

        if (assets > 0) {
            shares = assets.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares).toUint128();
        } else {
            assets = shares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares).toUint128();
        }

        user[id][onBehalf].borrowShares -= shares;
        market[id].totalBorrowShares -= shares;
        market[id].totalBorrowAssets -= assets;

        emit EventsLib.Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoRepayCallback(msg.sender).onMorphoRepay(assets, data);

        IERC20(info.borrowableToken).safeTransferFrom(msg.sender, address(this), assets);

        return (assets, shares);
    }

    /* COLLATERAL MANAGEMENT */

    /// @inheritdoc IMorpho
    function supplyCollateral(Info memory info, uint128 assets, address onBehalf, bytes calldata data) external {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        // Don't accrue interest because it's not required and it saves gas.

        user[id][onBehalf].collateral += assets;

        emit EventsLib.SupplyCollateral(id, msg.sender, onBehalf, assets);

        if (data.length > 0) IMorphoSupplyCollateralCallback(msg.sender).onMorphoSupplyCollateral(assets, data);

        IERC20(info.collateralToken).safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @inheritdoc IMorpho
    function withdrawCollateral(Info memory info, uint128 assets, address onBehalf, address receiver) external {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest(info, id);

        user[id][onBehalf].collateral -= assets;

        emit EventsLib.WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);

        require(_isHealthy(info, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);

        IERC20(info.collateralToken).safeTransfer(receiver, assets);
    }

    /* LIQUIDATION */

    /// @inheritdoc IMorpho
    function liquidate(Info memory info, address borrower, uint256 seized, bytes calldata data)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(seized != 0, ErrorsLib.ZERO_ASSETS);

        _accrueInterest(info, id);

        uint256 collateralPrice = IOracle(info.oracle).price();

        require(!_isHealthy(info, id, borrower, collateralPrice), ErrorsLib.HEALTHY_POSITION);

        assetsRepaid =
            seized.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(liquidationIncentiveFactor(info.lltv));
        sharesRepaid = assetsRepaid.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        require(assetsRepaid < 2 ** 128 && sharesRepaid < 2 ** 128, "too high");

        user[id][borrower].borrowShares -= uint128(sharesRepaid);
        market[id].totalBorrowShares -= uint128(sharesRepaid);
        market[id].totalBorrowAssets -= uint128(assetsRepaid);

        user[id][borrower].collateral -= uint128(seized);

        // Realize the bad debt if needed.
        uint256 badDebtShares;
        if (user[id][borrower].collateral == 0) {
            badDebtShares = user[id][borrower].borrowShares;
            uint256 badDebt = badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
            require(badDebt < 2 ** 128 && badDebtShares < 2 ** 128, "too high");
            market[id].totalSupplyAssets -= uint128(badDebt);
            market[id].totalBorrowAssets -= uint128(badDebt);
            market[id].totalBorrowShares -= uint128(badDebtShares);
            user[id][borrower].borrowShares = 0;
        }

        IERC20(info.collateralToken).safeTransfer(msg.sender, seized);

        emit EventsLib.Liquidate(id, msg.sender, borrower, assetsRepaid, sharesRepaid, seized, badDebtShares);

        if (data.length > 0) IMorphoLiquidateCallback(msg.sender).onMorphoLiquidate(assetsRepaid, data);

        IERC20(info.borrowableToken).safeTransferFrom(msg.sender, address(this), assetsRepaid);
    }

    /* FLASH LOANS */

    /// @inheritdoc IMorpho
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

    function _isSenderAuthorized(address theUser) internal view returns (bool) {
        return msg.sender == theUser || isAuthorized[theUser][msg.sender];
    }

    /* INTEREST MANAGEMENT */

    /// @inheritdoc IMorpho
    function accrueInterest(Info memory info) external {
        Id id = info.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);

        _accrueInterest(info, id);
    }

    /// @dev Accrues interest for `market`.
    /// @dev Assumes the given `market` and `id` match.
    function _accrueInterest(Info memory info, Id id) internal {
        uint256 elapsed = block.timestamp - market[id].lastUpdate;

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = market[id].totalBorrowAssets;

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = IIrm(info.irm).borrowRate(info);
            uint256 interest = marketTotalBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            require(interest < 2 ** 128, "too high");
            market[id].totalBorrowAssets += uint128(interest);
            market[id].totalSupplyAssets += uint128(interest);

            uint256 feeShares;
            if (market[id].fee != 0) {
                uint256 feeAmount = interest.wMulDown(market[id].fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares =
                    feeAmount.toSharesDown(market[id].totalSupplyAssets - feeAmount, market[id].totalSupplyShares);
                require(feeShares < 2 ** 128, "too high");
                user[id][feeRecipient].supplyShares += feeShares;
                market[id].totalSupplyShares += uint128(feeShares);
            }

            emit EventsLib.AccrueInterest(id, borrowRate, interest, feeShares);
        }

        market[id].lastUpdate = uint128(block.timestamp);
    }

    /* HEALTH CHECK */

    /// @dev Returns whether the position of `user` in the given `market` is healthy.
    /// @dev Assumes the given `market` and `id` match.
    function _isHealthy(Info memory info, Id id, address borrower) internal view returns (bool) {
        if (user[id][borrower].borrowShares == 0) return true;

        uint256 collateralPrice = IOracle(info.oracle).price();

        return _isHealthy(info, id, borrower, collateralPrice);
    }

    /// @dev Returns whether the position of `user` in the given `market` with the given `collateralPrice` is healthy.
    /// @dev Assumes the given `market` and `id` match.
    function _isHealthy(Info memory info, Id id, address borrower, uint256 collateralPrice)
        internal
        view
        returns (bool)
    {
        uint256 borrowed = uint256(user[id][borrower].borrowShares).toAssetsUp(
            market[id].totalBorrowAssets, market[id].totalBorrowShares
        );
        uint256 maxBorrow =
            uint256(user[id][borrower].collateral).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(info.lltv);

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

    /* LIQUIDATION INCENTIVE FACTOR */

    /// @dev The liquidation incentive factor is min(maxIncentiveFactor, 1/(1 - cursor*(1 - lltv))).
    function liquidationIncentiveFactor(uint256 lltv) private pure returns (uint256) {
        return
            UtilsLib.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
    }
}
