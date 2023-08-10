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

uint256 constant MAX_FEE = 0.25e18;
uint256 constant ALPHA = 0.5e18;

/// @dev The EIP-712 typeHash for EIP712Domain.
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The EIP-712 typeHash for Authorization.
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");

contract Blue is IBlue {
    using MarketLib for Market;
    using MarketLib for MarketParams;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    // Immutables.

    bytes32 public immutable DOMAIN_SEPARATOR;

    /* INTERNAL STORAGE */

    // Markets.
    mapping(Id => Market) internal _market;

    /* PUBLIC STORAGE */

    // Owner.
    address public owner;
    // Fee recipient.
    address public feeRecipient;
    // Enabled IRMs.
    mapping(address => bool) public isIrmEnabled;
    // Enabled LLTVs.
    mapping(uint256 => bool) public isLltvEnabled;
    // User's authorizations. Note that by default, msg.sender is authorized by themself.
    mapping(address => mapping(address => bool)) public isAuthorized;
    // User's nonces. Used to prevent replay attacks with EIP-712 signatures.
    mapping(address => uint256) public nonce;

    // Constructor.

    constructor(address newOwner) {
        owner = newOwner;

        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Blue"), block.chainid, address(this)));
    }

    // Modifiers.

    modifier onlyOwner() {
        require(msg.sender == owner, ErrorsLib.NOT_OWNER);
        _;
    }

    // Only owner functions.

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;

        emit EventsLib.SetOwner(newOwner);
    }

    function enableIrm(address irm) external onlyOwner {
        isIrmEnabled[irm] = true;

        emit EventsLib.EnableIrm(address(irm));
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, ErrorsLib.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;

        emit EventsLib.EnableLltv(lltv);
    }

    /// @notice It is the owner's responsibility to ensure a fee recipient is set before setting a non-zero fee.
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

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit EventsLib.SetFeeRecipient(recipient);
    }

    // Markets management.

    function createMarket(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(isIrmEnabled[marketParams.irm], ErrorsLib.IRM_NOT_ENABLED);
        require(isLltvEnabled[marketParams.lltv], ErrorsLib.LLTV_NOT_ENABLED);
        require(market.lastUpdate() == 0, ErrorsLib.MARKET_CREATED);

        market.setLastUpdate(block.timestamp);

        emit EventsLib.CreateMarket(id, marketParams);
    }

    // Supply management.

    function supply(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, bytes calldata data)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(amount, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(marketParams, id);

        if (amount > 0) shares = amount.toSharesDown(market.totalSupply(), market.totalSupplyShares());
        else amount = shares.toAssetsUp(market.totalSupply(), market.totalSupplyShares());

        market.setSupplyShares(onBehalf, market.supplyShares(onBehalf) + shares);
        market.setTotalSupplyShares(market.totalSupplyShares() + shares);
        market.setTotalSupply(market.totalSupply() + amount);

        emit EventsLib.Supply(id, msg.sender, onBehalf, amount, shares);

        if (data.length > 0) IBlueSupplyCallback(msg.sender).onBlueSupply(amount, data);

        IERC20(marketParams.borrowableAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, address receiver)
        external
    {
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

        market.setSupplyShares(onBehalf, market.supplyShares(onBehalf) - shares);
        market.setTotalSupplyShares(market.totalSupplyShares() - shares);
        market.setTotalSupply(market.totalSupply() - amount);

        emit EventsLib.Withdraw(id, msg.sender, onBehalf, receiver, amount, shares);

        require(market.totalBorrow() <= market.totalSupply(), ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(marketParams.borrowableAsset).safeTransfer(receiver, amount);
    }

    // Borrow management.

    function borrow(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, address receiver)
        external
    {
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

        market.setBorrowShares(onBehalf, market.borrowShares(onBehalf) + shares);
        market.setTotalBorrowShares(market.totalBorrowShares() + shares);
        market.setTotalBorrow(market.totalBorrow() + amount);

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, amount, shares);

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(market.totalBorrow() <= market.totalSupply(), ErrorsLib.INSUFFICIENT_LIQUIDITY);

        IERC20(marketParams.borrowableAsset).safeTransfer(receiver, amount);
    }

    function repay(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, bytes calldata data)
        external
    {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(amount, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterests(marketParams, id);

        if (amount > 0) shares = amount.toSharesDown(market.totalBorrow(), market.totalBorrowShares());
        else amount = shares.toAssetsUp(market.totalBorrow(), market.totalBorrowShares());

        market.setBorrowShares(onBehalf, market.borrowShares(onBehalf) - shares);
        market.setTotalBorrowShares(market.totalBorrowShares() - shares);
        market.setTotalBorrow(market.totalBorrow() - amount);

        emit EventsLib.Repay(id, msg.sender, onBehalf, amount, shares);

        if (data.length > 0) IBlueRepayCallback(msg.sender).onBlueRepay(amount, data);

        IERC20(marketParams.borrowableAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(MarketParams memory marketParams, uint256 amount, address onBehalf, bytes calldata data) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(amount != 0, ErrorsLib.ZERO_AMOUNT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        // Don't accrue interests because it's not required and it saves gas.

        market.setCollateral(onBehalf, market.collateral(onBehalf) + amount);

        emit EventsLib.SupplyCollateral(id, msg.sender, onBehalf, amount);

        if (data.length > 0) IBlueSupplyCollateralCallback(msg.sender).onBlueSupplyCollateral(amount, data);

        IERC20(marketParams.collateralAsset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(MarketParams memory marketParams, uint256 amount, address onBehalf, address receiver) external {
        Id id = marketParams.id();
        Market storage market = _market[id];

        require(market.lastUpdate() != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(amount != 0, ErrorsLib.ZERO_AMOUNT);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterests(marketParams, id);

        market.setCollateral(onBehalf, market.collateral(onBehalf) - amount);

        emit EventsLib.WithdrawCollateral(id, msg.sender, onBehalf, receiver, amount);

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);

        IERC20(marketParams.collateralAsset).safeTransfer(receiver, amount);
    }

    // Liquidation.

    function liquidate(MarketParams memory marketParams, address borrower, uint256 seized, bytes calldata data) external {
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

        market.setBorrowShares(borrower, market.borrowShares(borrower) - repaidShares);
        market.setTotalBorrowShares(market.totalBorrowShares() - repaidShares);
        market.setTotalBorrow(market.totalBorrow() - repaid);

        market.setCollateral(borrower, market.collateral(borrower) - seized);

        // Realize the bad debt if needed.
        uint256 badDebtShares;
        if (market.collateral(borrower) == 0) {
            badDebtShares = market.borrowShares(borrower);
            uint256 badDebt = badDebtShares.toAssetsUp(market.totalBorrow(), market.totalBorrowShares());
            market.setTotalSupply(market.totalSupply() - badDebt);
            market.setTotalBorrow(market.totalBorrow() - badDebt);
            market.setTotalBorrowShares(market.totalBorrowShares() - badDebtShares);
            market.setBorrowShares(borrower, 0);
        }

        IERC20(marketParams.collateralAsset).safeTransfer(msg.sender, seized);

        emit EventsLib.Liquidate(id, msg.sender, borrower, repaid, repaidShares, seized, badDebtShares);

        if (data.length > 0) IBlueLiquidateCallback(msg.sender).onBlueLiquidate(repaid, data);

        IERC20(marketParams.borrowableAsset).safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Flash Loans.

    function flashLoan(address token, uint256 amount, bytes calldata data) external {
        IERC20(token).safeTransfer(msg.sender, amount);

        emit EventsLib.FlashLoan(msg.sender, token, amount);

        IBlueFlashLoanCallback(msg.sender).onBlueFlashLoan(amount, data);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // Authorizations.

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;

        emit EventsLib.SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized);
    }

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

    // Interests management.

    function _accrueInterests(MarketParams memory marketParams, Id id) internal {
        Market storage market = _market[id];

        uint256 elapsed = block.timestamp - market.lastUpdate();

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = market.totalBorrow();

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRate(marketParams);
            uint256 accruedInterests = marketTotalBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            market.setTotalBorrow(marketTotalBorrow + accruedInterests);
            market.setTotalSupply(market.totalSupply() + accruedInterests);

            uint256 feeShares;
            if (market.fee() != 0) {
                uint256 feeAmount = accruedInterests.wMulDown(market.fee());
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares = feeAmount.mulDivDown(market.totalSupplyShares(), market.totalSupply() - feeAmount);
                market.setSupplyShares(feeRecipient, market.supplyShares(feeRecipient) + feeShares);
                market.setTotalSupplyShares(market.totalSupplyShares() + feeShares);
            }

            emit EventsLib.AccrueInterests(id, borrowRate, accruedInterests, feeShares);
        }

        market.setLastUpdate(block.timestamp);
    }

    // Health check.

    function _isHealthy(MarketParams memory marketParams, Id id, address user) internal view returns (bool) {
        Market storage market = _market[id];

        if (market.borrowShares(user) == 0) return true;

        (uint256 collateralPrice, uint256 priceScale) = IOracle(marketParams.oracle).price();

        return _isHealthy(marketParams, id, user, collateralPrice, priceScale);
    }

    function _isHealthy(MarketParams memory marketParams, Id id, address user, uint256 collateralPrice, uint256 priceScale)
        internal
        view
        returns (bool)
    {
        Market storage market = _market[id];

        uint256 borrowed = market.borrowShares(user).toAssetsUp(market.totalBorrow(), market.totalBorrowShares());
        uint256 maxBorrow = market.collateral(user).mulDivDown(collateralPrice, priceScale).wMulDown(marketParams.lltv);

        return maxBorrow >= borrowed;
    }

    // Storage view.

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
