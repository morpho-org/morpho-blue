// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {SharesMath} from "src/libraries/SharesMath.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {Id, Market, MarketLib} from "src/libraries/MarketLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {Owned} from "solmate/auth/Owned.sol";

uint256 constant WAD = 1e18;
uint256 constant ALPHA = 0.5e18;

/// @dev The prefix used for EIP-712 signature.
string constant EIP712_MSG_PREFIX = "\x19\x01";

/// @dev The name used for EIP-712 signature.
string constant EIP712_NAME = "Blue";

/// @dev The domain typehash used for the EIP-712 signature.
bytes32 constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The typehash for approveManagerWithSig Authorization used for the EIP-712 signature.
bytes32 constant EIP712_AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address delegator,address manager,bool approval,uint256 nonce,uint256 deadline)");

/// @dev The highest valid value for s in an ECDSA signature pair (0 < s < secp256k1n ÷ 2 + 1).
uint256 constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

contract Blue {
    using SharesMath for uint256;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for IERC20;
    using MarketLib for Market;

    // Immutables.

    bytes32 public immutable domainSeparator;

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
    // User's managers.
    mapping(address => mapping(address => bool)) public isApproved;
    // User's nonces. Used to prevent replay attacks with EIP-712 signatures.
    mapping(address => uint256) public userNonce;

    // Constructor.

    constructor(address newOwner) {
        owner = newOwner;

        domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256(bytes(EIP712_NAME)), block.chainid, address(this)));
    }

    // Modifiers.

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    // Only owner functions.

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function enableIrm(IIrm irm) external onlyOwner {
        isIrmEnabled[irm] = true;

        emit Events.IrmEnabled(address(irm));
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, Errors.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;

        emit Events.LltvEnabled(lltv);
    }

    // @notice It is the owner's responsibility to ensure a fee recipient is set before setting a non-zero fee.
    function setFee(Market calldata market, uint256 newFee) external onlyOwner {
        Id id = market.id();
        require(lastUpdate[id] != 0, "unknown market");
        require(newFee <= WAD, "fee must be <= 1");
        fee[id] = newFee;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;
    }

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = market.id();
        require(isIrmEnabled[market.irm], Errors.IRM_NOT_ENABLED);
        require(isLltvEnabled[market.lltv], Errors.LLTV_NOT_ENABLED);
        require(lastUpdate[id] == 0, Errors.MARKET_CREATED);

        _accrueInterests(market, id);
    }

    // Supply management.

    function supply(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesDown(totalSupply[id], totalSupplyShares[id]);
        supplyShare[id][onBehalf] += shares;
        totalSupplyShares[id] += shares;

        totalSupply[id] += amount;

        emit Events.Supply(Id.unwrap(id), msg.sender, onBehalf, amount, shares);

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderOrIsApproved(onBehalf), Errors.MANAGER_NOT_APPROVED);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesUp(totalSupply[id], totalSupplyShares[id]);
        supplyShare[id][onBehalf] -= shares;
        totalSupplyShares[id] -= shares;

        totalSupply[id] -= amount;

        emit Events.Withdraw(Id.unwrap(id), msg.sender, onBehalf, amount, shares);

        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderOrIsApproved(onBehalf), Errors.MANAGER_NOT_APPROVED);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesUp(totalBorrow[id], totalBorrowShares[id]);
        borrowShare[id][onBehalf] += shares;
        totalBorrowShares[id] += shares;

        totalBorrow[id] += amount;

        emit Events.Borrow(Id.unwrap(id), msg.sender, onBehalf, amount, shares);

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);
        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        uint256 shares = amount.toSharesDown(totalBorrow[id], totalBorrowShares[id]);
        borrowShare[id][onBehalf] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        emit Events.Repay(Id.unwrap(id), msg.sender, onBehalf, amount, shares);

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][onBehalf] += amount;

        emit Events.CollateralSupply(Id.unwrap(id), msg.sender, onBehalf, amount);

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(amount != 0, Errors.ZERO_AMOUNT);
        require(_isSenderOrIsApproved(onBehalf), Errors.MANAGER_NOT_APPROVED);

        _accrueInterests(market, id);

        collateral[id][onBehalf] -= amount;

        emit Events.CollateralWithdraw(Id.unwrap(id), msg.sender, onBehalf, amount);

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);

        market.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(Market calldata market, address borrower, uint256 seized) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(seized != 0, Errors.ZERO_AMOUNT);

        _accrueInterests(market, id);

        require(!_isHealthy(market, id, borrower), Errors.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.mulWadDown(WAD.divWadDown(market.lltv) - WAD);
        uint256 repaid = seized.mulWadUp(market.collateralOracle.price()).divWadUp(incentive).divWadUp(
            market.borrowableOracle.price()
        );
        uint256 repaidShares = repaid.toSharesDown(totalBorrow[id], totalBorrowShares[id]);

        borrowShare[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        emit Events.Liquidation(Id.unwrap(id), msg.sender, borrower, repaid, repaidShares, seized);

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            uint256 badDebtShares = borrowShare[id][borrower];
            uint256 badDebt = badDebtShares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]);
            totalSupply[id] -= badDebt;
            totalBorrow[id] -= badDebt;
            totalBorrowShares[id] -= badDebtShares;
            borrowShare[id][borrower] = 0;

            emit Events.BadDebtRealized(Id.unwrap(id), borrower, badDebt, badDebtShares);
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);
        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Position management.

    function setApproval(
        address delegator,
        address manager,
        bool approval,
        uint256 nonce,
        uint256 deadline,
        Signature calldata signature
    ) external {
        require(uint256(signature.s) <= MAX_VALID_ECDSA_S, Errors.INVALID_S);
        // v ∈ {27, 28} (source: https://ethereum.github.io/yellowpaper/paper.pdf #308)
        require(signature.v == 27 || signature.v == 28, Errors.INVALID_V);

        bytes32 structHash =
            keccak256(abi.encode(EIP712_AUTHORIZATION_TYPEHASH, delegator, manager, approval, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked(EIP712_MSG_PREFIX, domainSeparator, structHash));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && delegator == signatory, Errors.INVALID_SIGNATORY);
        require(block.timestamp < deadline, Errors.SIGNATURE_EXPIRED);
        require(nonce == userNonce[signatory]++, Errors.INVALID_NONCE);

        _setApproval(signatory, manager, approval);
    }

    function setApproval(address manager, bool approval) external {
        _setApproval(msg.sender, manager, approval);
    }

    function _setApproval(address delegator, address manager, bool approval) internal {
        isApproved[delegator][manager] = approval;

        emit Events.Approval(msg.sender, delegator, manager, approval);
    }

    function _isSenderOrIsApproved(address user) internal view returns (bool) {
        return msg.sender == user || isApproved[user][msg.sender];
    }

    // Interests management.

    function _accrueInterests(Market calldata market, Id id) internal {
        uint256 marketTotalBorrow = totalBorrow[id];

        uint256 accruedInterests;
        if (marketTotalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            accruedInterests = marketTotalBorrow.mulWadDown(borrowRate * (block.timestamp - lastUpdate[id]));
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

        emit Events.InterestsAccrued(Id.unwrap(id), accruedInterests);
    }

    // Health check.

    function _isHealthy(Market calldata market, Id id, address user) internal view returns (bool) {
        uint256 borrowShares = borrowShare[id][user];
        if (borrowShares == 0) return true;

        // totalBorrowShares[id] > 0 when borrowShares > 0.
        uint256 borrowValue =
            borrowShares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]).mulWadUp(market.borrowableOracle.price());
        uint256 collateralValue = collateral[id][user].mulWadDown(market.collateralOracle.price());
        return collateralValue.mulWadDown(market.lltv) >= borrowValue;
    }
}
