// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

uint256 constant WAD = 1e18;
uint256 constant ALPHA = 0.5e18;

/// @dev The prefix used for EIP-712 signature.
string constant EIP712_MSG_PREFIX = "\x19\x01";

/// @dev The name used for EIP-712 signature.
string constant EIP712_NAME = "Blue";

/// @dev The version used for EIP-712 signature.
string constant EIP712_VERSION = "0";

/// @dev The domain typehash used for the EIP-712 signature.
bytes32 constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

/// @dev The typehash for approveManagerWithSig Authorization used for the EIP-712 signature.
bytes32 constant EIP712_AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address delegator,address manager,bool isAllowed,uint256 nonce,uint256 deadline)");

/// @dev The highest valid value for s in an ECDSA signature pair (0 < s < secp256k1n ÷ 2 + 1).
uint256 constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

// Market id.
type Id is bytes32;

// Market.
struct Market {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    IIrm irm;
    uint256 lltv;
}

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

using {toId} for Market;

function toId(Market calldata market) pure returns (Id) {
    return Id.wrap(keccak256(abi.encode(market)));
}

contract Blue {
    using MathLib for uint256;
    using SafeTransferLib for IERC20;

    // Immutables.

    bytes32 public immutable domainSeparator;

    // Storage.

    // Owner.
    address public owner;
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
    // Enabled IRMs.
    mapping(IIrm => bool) public isIrmEnabled;
    // Enabled LLTVs.
    mapping(uint256 => bool) public isLltvEnabled;
    // User's managers.
    mapping(address => mapping(address => bool)) public approval;
    // User's nonces.
    mapping(address => uint256) public userNonce;

    // Constructor.

    constructor(address newOwner) {
        owner = newOwner;

        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(EIP712_NAME)),
                keccak256(bytes(EIP712_VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    // Modifiers.

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // Only owner functions.

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function enableIrm(IIrm irm) external onlyOwner {
        isIrmEnabled[irm] = true;
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < WAD, "LLTV too high");
        isLltvEnabled[lltv] = true;
    }

    // Markets management.

    function createMarket(Market calldata market) external {
        Id id = market.toId();
        require(isIrmEnabled[market.irm], "IRM not enabled");
        require(isLltvEnabled[market.lltv], "LLTV not enabled");
        require(lastUpdate[id] == 0, "market already exists");

        accrueInterests(market, id);
    }

    // Supply management.

    function supply(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market, id);

        if (totalSupply[id] == 0) {
            supplyShare[id][msg.sender] = WAD;
            totalSupplyShares[id] = WAD;
        } else {
            uint256 shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
            supplyShare[id][msg.sender] += shares;
            totalSupplyShares[id] += shares;
        }

        totalSupply[id] += amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");
        require(_isSenderApprovedFor(onBehalf), "not approved");

        accrueInterests(market, id);

        uint256 shares = amount.wMul(totalSupplyShares[id]).wDiv(totalSupply[id]);
        supplyShare[id][onBehalf] -= shares;
        totalSupplyShares[id] -= shares;

        totalSupply[id] -= amount;

        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    // Borrow management.

    function borrow(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");
        require(_isSenderApprovedFor(onBehalf), "not approved");

        accrueInterests(market, id);

        if (totalBorrow[id] == 0) {
            borrowShare[id][onBehalf] = WAD;
            totalBorrowShares[id] = WAD;
        } else {
            uint256 shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
            borrowShare[id][onBehalf] += shares;
            totalBorrowShares[id] += shares;
        }

        totalBorrow[id] += amount;

        require(isHealthy(market, id, onBehalf), "not enough collateral");
        require(totalBorrow[id] <= totalSupply[id], "not enough liquidity");

        market.borrowableAsset.safeTransfer(msg.sender, amount);
    }

    function repay(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        accrueInterests(market, id);

        uint256 shares = amount.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);
        borrowShare[id][msg.sender] -= shares;
        totalBorrowShares[id] -= shares;

        totalBorrow[id] -= amount;

        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Collateral management.

    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market calldata market, uint256 amount) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");

        // Don't accrue interests because it's not required and it saves gas.

        collateral[id][msg.sender] += amount;

        market.collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Market calldata market, uint256 amount, address onBehalf) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(amount != 0, "zero amount");
        require(_isSenderApprovedFor(onBehalf), "not approved");

        accrueInterests(market, id);

        collateral[id][onBehalf] -= amount;

        require(isHealthy(market, id, onBehalf), "not enough collateral");

        market.collateralAsset.safeTransfer(msg.sender, amount);
    }

    // Liquidation.

    function liquidate(Market calldata market, address borrower, uint256 seized) external {
        Id id = market.toId();
        require(lastUpdate[id] != 0, "unknown market");
        require(seized != 0, "zero amount");

        accrueInterests(market, id);

        require(!isHealthy(market, id, borrower), "cannot liquidate a healthy position");

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = WAD + ALPHA.wMul(WAD.wDiv(market.lltv) - WAD);
        uint256 repaid =
            seized.wMul(market.collateralOracle.price()).wDiv(incentive).wDiv(market.borrowableOracle.price());
        uint256 repaidShares = repaid.wMul(totalBorrowShares[id]).wDiv(totalBorrow[id]);

        borrowShare[id][borrower] -= repaidShares;
        totalBorrowShares[id] -= repaidShares;
        totalBorrow[id] -= repaid;

        collateral[id][borrower] -= seized;

        // Realize the bad debt if needed.
        if (collateral[id][borrower] == 0) {
            totalSupply[id] -= borrowShare[id][borrower].wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]);
            totalBorrowShares[id] -= borrowShare[id][borrower];
            borrowShare[id][borrower] = 0;
        }

        market.collateralAsset.safeTransfer(msg.sender, seized);
        market.borrowableAsset.safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Position management.

    function setApproval(
        address delegator,
        address manager,
        bool isAllowed,
        uint256 nonce,
        uint256 deadline,
        Signature calldata signature
    ) external {
        require(uint256(signature.s) <= MAX_VALID_ECDSA_S, "invalid s");
        // v ∈ {27, 28} (source: https://ethereum.github.io/yellowpaper/paper.pdf #308)
        require(signature.v == 27 || signature.v == 28, "invalid v");

        bytes32 structHash =
            keccak256(abi.encode(EIP712_AUTHORIZATION_TYPEHASH, delegator, manager, isAllowed, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked(EIP712_MSG_PREFIX, domainSeparator, structHash));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require((signatory != address(0) && delegator == signatory), "invalid signatory");
        require(block.timestamp < deadline, "signature expired");

        require(nonce == userNonce[signatory]++, "invalid nonce");

        _setApproval(signatory, manager, isAllowed);
    }

    function setApproval(address manager, bool isAllowed) external {
        _setApproval(msg.sender, manager, isAllowed);
    }

    function _setApproval(address delegator, address manager, bool isAllowed) internal {
        approval[delegator][manager] = isAllowed;
    }

    function _isSenderApprovedFor(address user) internal view returns (bool) {
        return msg.sender == user || approval[user][msg.sender];
    }

    // Interests management.

    function accrueInterests(Market calldata market, Id id) private {
        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            uint256 accruedInterests = marketTotalBorrow.wMul(borrowRate).wMul(block.timestamp - lastUpdate[id]);
            totalBorrow[id] = marketTotalBorrow + accruedInterests;
            totalSupply[id] += accruedInterests;
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function isHealthy(Market calldata market, Id id, address user) private view returns (bool) {
        uint256 borrowShares = borrowShare[id][user];
        if (borrowShares == 0) return true;
        // totalBorrowShares[id] > 0 when borrowShares > 0.
        uint256 borrowValue =
            borrowShares.wMul(totalBorrow[id]).wDiv(totalBorrowShares[id]).wMul(market.borrowableOracle.price());
        uint256 collateralValue = collateral[id][user].wMul(market.collateralOracle.price());
        return collateralValue.wMul(market.lltv) >= borrowValue;
    }
}
