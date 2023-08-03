// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {
    IBlueLiquidateCallback,
    IBlueRepayCallback,
    IBlueSupplyCallback,
    IBlueSupplyCollateralCallback
} from "src/interfaces/IBlueCallbacks.sol";
import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFlashLender} from "src/interfaces/IFlashLender.sol";
import {IFlashBorrower} from "src/interfaces/IFlashBorrower.sol";

import {Errors} from "./libraries/Errors.sol";
import {SharesMath} from "src/libraries/SharesMath.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {Id, Market, MarketLib} from "src/libraries/MarketLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint256 constant MAX_FEE = 0.25e18;
uint256 constant ALPHA = 0.5e18;

/// @dev The EIP-712 typeHash for EIP712Domain.
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The EIP-712 typeHash for Authorization.
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

contract Blue is IFlashLender {
    using SharesMath for uint256;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for IERC20;
    using MarketLib for Market;

    // Immutables.

    bytes32 public immutable DOMAIN_SEPARATOR;

    // Storage.

    // Owner.
    address public owner;
    // Fee recipient.
    address public feeRecipient;
    // User' supply balances.
    mapping(Id => mapping(address => uint256)) public supplyShare;
    // User' borrow balances.
    mapping(Id => mapping(address => uint256)) public borrowShare;
    // User' collateral balance.
    mapping(Id => mapping(address => uint256)) public collateral;
    // Market total supply.
    mapping(Id => uint256) public totalSupply;
    // Market total supply shares.
    mapping(Id => uint256) public totalSupplyShares;
    // Market total borrow.
    mapping(Id => uint256) public totalBorrow;
    // Market total borrow shares.
    mapping(Id => uint256) public totalBorrowShares;
    // Interests last update (used to check if a market has been created).
    mapping(Id => uint256) public lastUpdate;
    // Fee.
    mapping(Id => uint256) public fee;
    // Enabled IRMs.
    mapping(IIrm => bool) public isIrmEnabled;
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
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    // Only owner functions.

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function enableIrm(IIrm irm) external onlyOwner {
        isIrmEnabled[irm] = true;
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < FixedPointMathLib.WAD, Errors.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;
    }

    /// @notice It is the owner's responsibility to ensure a fee recipient is set before setting a non-zero fee.
    function setFee(Market memory market, uint256 newFee) external onlyOwner {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, Errors.MAX_FEE_EXCEEDED);
        fee[id] = newFee;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;
    }

    // Markets management.

    function createMarket(Market memory market) external {
        Id id = market.id();
        require(isIrmEnabled[market.irm], Errors.IRM_NOT_ENABLED);
        require(isLltvEnabled[market.lltv], Errors.LLTV_NOT_ENABLED);
        require(lastUpdate[id] == 0, Errors.MARKET_CREATED);

        _accrueInterests(market, id);
    }

    // Supply management.

    function supply(Market memory market, uint256 amount, address onBehalf, bytes calldata data)
        external
        returns (uint256 shares)
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        shares = amount.toSharesDown(totalSupply[id], totalSupplyShares[id]);

        supplyShare[id][onBehalf] += shares;
        totalSupplyShares[id] += shares;
        totalSupply[id] += amount;

        if (data.length > 0) IBlueSupplyCallback(msg.sender).onBlueSupply(amount, data);

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market memory market, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256 amount)
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(shares != 0, Errors.ZERO_AMOUNT);
        require(_isSenderAuthorized(onBehalf), Errors.UNAUTHORIZED);

        _accrueInterests(market, id);

        amount = shares.toAssetsDown(totalSupply[id], totalSupplyShares[id]);

        supplyShare[id][onBehalf] -= shares;
        totalSupplyShares[id] -= shares;
        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(receiver, amount);
    }

    // Borrow management.

    function borrow(Market memory market, uint256 amount, address onBehalf, address receiver)
        external
        returns (uint256 shares)
    {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderAuthorized(onBehalf), Errors.UNAUTHORIZED);

        _accrueInterests(market, id);

        shares = amount.toSharesUp(totalBorrow[id], totalBorrowShares[id]);

        borrowShare[id][onBehalf] += shares;
        totalBorrowShares[id] += shares;
        totalBorrow[id] += amount;

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);
        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(receiver, amount);
    }

    function repay(Market memory market, uint256 shares, address onBehalf, bytes calldata data)
        external
        returns (uint256 amount)
    {
        Id id = market.id();
        require(shares != 0, Errors.ZERO_AMOUNT);
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);

        _accrueInterests(market, id);

        amount = shares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]);

        borrowShare[id][onBehalf] -= shares;
        totalBorrowShares[id] -= shares;
        totalBorrow[id] -= amount;

        if (data.length > 0) IBlueRepayCallback(msg.sender).onBlueRepay(amount, data);

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market memory market, uint256 amount, address onBehalf, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][onBehalf] += amount;

        if (data.length > 0) {
            IBlueSupplyCollateralCallback(msg.sender).onBlueSupplyCollateral(amount, data);
        }

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market memory market, uint256 amount, address onBehalf, address receiver) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderAuthorized(onBehalf), Errors.UNAUTHORIZED);

        _accrueInterests(market, id);

        collateral[id][onBehalf] -= amount;

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);

        market.collateralAsset.safeTransfer(receiver, amount);
    }

    // Liquidation.

    function liquidate(Market memory market, address borrower, uint256 seized, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(seized != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        require(!_isHealthy(market, id, borrower, collateralPrice, borrowablePrice), Errors.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);
        uint256 repaid = seized.mulWadUp(collateralPrice).divWadUp(incentive).divWadUp(borrowablePrice);
        uint256 repaidShares = repaid.toSharesDown(totalBorrow[id], totalBorrowShares[id]);

        borrowShare[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            uint256 badDebt = borrowShare[id][borrower].toAssetsUp(totalBorrow[id], totalBorrowShares[id]);
            totalSupply[id] -= badDebt;
            totalBorrow[id] -= badDebt;
            totalBorrowShares[id] -= borrowShare[id][borrower];
            borrowShare[id][borrower] = 0;
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);

        if (data.length > 0) IBlueLiquidateCallback(msg.sender).onBlueLiquidate(seized, repaid, data);

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Flash Loans.

    /// @inheritdoc IFlashLender
    function flashLoan(IFlashBorrower receiver, address token, uint256 amount, bytes calldata data) external {
        IERC20(token).safeTransfer(address(receiver), amount);

        receiver.onBlueFlashLoan(msg.sender, token, amount, data);

        IERC20(token).safeTransferFrom(address(receiver), address(this), amount);
    }

    // Authorizations.

    /// @dev The signature is malleable, but it has no impact on the security here.
    function setAuthorization(
        address authorizer,
        address authorized,
        bool newIsAuthorized,
        uint256 deadline,
        Signature calldata signature
    ) external {
        require(block.timestamp < deadline, Errors.SIGNATURE_EXPIRED);

        bytes32 hashStruct = keccak256(
            abi.encode(AUTHORIZATION_TYPEHASH, authorizer, authorized, newIsAuthorized, nonce[authorizer]++, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && authorizer == signatory, Errors.INVALID_SIGNATURE);

        isAuthorized[signatory][authorized] = newIsAuthorized;
    }

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
    }

    function _isSenderAuthorized(address user) internal view returns (bool) {
        return msg.sender == user || isAuthorized[user][msg.sender];
    }

    // Interests management.

    function _accrueInterests(Market memory market, Id id) internal {
        uint256 elapsed = block.timestamp - lastUpdate[id];

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.mulWadDown(borrowRate * elapsed);
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
            totalSupply[id] += accruedInterests;

            if (fee[id] != 0) {
                uint256 feeAmount = accruedInterests.mulWadDown(fee[id]);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.mulDivDown(totalSupplyShares[id], totalSupply[id] - feeAmount);
                supplyShare[id][feeRecipient] += feeShares;
                totalSupplyShares[id] += feeShares;
            }
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function _isHealthy(Market memory market, Id id, address user) internal view returns (bool) {
        if (borrowShare[id][user] == 0) return true;

        uint256 collateralPrice = market.collateralOracle.price();
        uint256 borrowablePrice = market.borrowableOracle.price();

        return _isHealthy(market, id, user, collateralPrice, borrowablePrice);
    }

    function _isHealthy(Market memory market, Id id, address user, uint256 collateralPrice, uint256 borrowablePrice)
        internal
        view
        returns (bool)
    {
        uint256 borrowValue =
            borrowShare[id][user].toAssetsUp(totalBorrow[id], totalBorrowShares[id]).mulWadUp(borrowablePrice);
        uint256 collateralValue = collateral[id][user].mulWadDown(collateralPrice);

        return collateralValue.mulWadDown(market.lltv) >= borrowValue;
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
}
