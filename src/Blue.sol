// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {
    IBlueLiquidateCallback,
    IBlueRepayCallback,
    IBlueSupplyCallback,
    IBlueSupplyCollateralCallback,
    IBlueFlashLoanCallback
} from "./interfaces/IBlueCallbacks.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {Id, Market, Signature, IBlue} from "./interfaces/IBlue.sol";

import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {SharesMath} from "./libraries/SharesMath.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

uint256 constant MAX_FEE = 0.25e18;
uint256 constant ALPHA = 0.5e18;

/// @dev The EIP-712 typeHash for EIP712Domain.
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The EIP-712 typeHash for Authorization.
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");

contract Blue is IBlue {
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
    mapping(Id => mapping(address => uint256)) public supplyShares;
    // User' borrow balances.
    mapping(Id => mapping(address => uint256)) public borrowShares;
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
    // Interest last update (used to check if a market has been created).
    mapping(Id => uint256) public lastUpdate;
    // Fee.
    mapping(Id => uint256) public fee;
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
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    // Only owner functions.

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;

        emit Events.SetOwner(newOwner);
    }

    function enableIrm(address irm) external onlyOwner {
        isIrmEnabled[irm] = true;

        emit Events.EnableIrm(address(irm));
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(lltv < FixedPointMathLib.WAD, Errors.LLTV_TOO_HIGH);
        isLltvEnabled[lltv] = true;

        emit Events.EnableLltv(lltv);
    }

    /// @notice It is the owner's responsibility to ensure a fee recipient is set before setting a non-zero fee.
    function setFee(Market memory market, uint256 newFee) external onlyOwner {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(newFee <= MAX_FEE, Errors.MAX_FEE_EXCEEDED);
        fee[id] = newFee;

        emit Events.SetFee(id, newFee);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;

        emit Events.SetFeeRecipient(recipient);
    }

    // Markets management.

    function createMarket(Market memory market) external {
        Id id = market.id();
        require(isIrmEnabled[market.irm], Errors.IRM_NOT_ENABLED);
        require(isLltvEnabled[market.lltv], Errors.LLTV_NOT_ENABLED);
        require(lastUpdate[id] == 0, Errors.MARKET_CREATED);
        lastUpdate[id] = block.timestamp;

        emit Events.CreateMarket(id, market);
    }

    // Supply management.

    function supplyAssets(Market memory market, uint256 assets, address onBehalf, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(assets != 0, Errors.ZERO_ASSETS);
        require(onBehalf != address(0), Errors.ZERO_ADDRESS);

        _accrueInterest(market, id);

        uint256 shares = assets.toSharesDown(totalSupply[id], totalSupplyShares[id]);

        supplyShares[id][onBehalf] += shares;
        totalSupplyShares[id] += shares;
        totalSupply[id] += assets;

        emit Events.Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IBlueSupplyCallback(msg.sender).onBlueSupply(assets, data);

        IERC20(market.borrowableAsset).safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdrawShares(Market memory market, uint256 shares, address onBehalf, address receiver) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(shares != 0, Errors.ZERO_SHARES);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), Errors.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), Errors.UNAUTHORIZED);

        _accrueInterest(market, id);

        uint256 assets = shares.toAssetsDown(totalSupply[id], totalSupplyShares[id]);

        supplyShares[id][onBehalf] -= shares;
        totalSupplyShares[id] -= shares;
        totalSupply[id] -= assets;

        emit Events.Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);

        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        IERC20(market.borrowableAsset).safeTransfer(receiver, assets);
    }

    // Borrow management.

    function borrowAssets(Market memory market, uint256 assets, address onBehalf, address receiver) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(assets != 0, Errors.ZERO_ASSETS);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), Errors.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), Errors.UNAUTHORIZED);

        _accrueInterest(market, id);

        uint256 shares = assets.toSharesUp(totalBorrow[id], totalBorrowShares[id]);

        borrowShares[id][onBehalf] += shares;
        totalBorrowShares[id] += shares;
        totalBorrow[id] += assets;

        emit Events.Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);
        require(totalBorrow[id] <= totalSupply[id], Errors.INSUFFICIENT_LIQUIDITY);

        IERC20(market.borrowableAsset).safeTransfer(receiver, assets);
    }

    function repayShares(Market memory market, uint256 shares, address onBehalf, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(shares != 0, Errors.ZERO_SHARES);
        require(onBehalf != address(0), Errors.ZERO_ADDRESS);

        _accrueInterest(market, id);

        uint256 assets = shares.toAssetsUp(totalBorrow[id], totalBorrowShares[id]);

        borrowShares[id][onBehalf] -= shares;
        totalBorrowShares[id] -= shares;
        totalBorrow[id] -= assets;

        emit Events.Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IBlueRepayCallback(msg.sender).onBlueRepay(assets, data);

        IERC20(market.borrowableAsset).safeTransferFrom(msg.sender, address(this), assets);
    }

    // Collateral management.

    /// @dev Don't accrue interest because it's not required and it saves gas.
    function supplyCollateral(Market memory market, uint256 assets, address onBehalf, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(assets != 0, Errors.ZERO_ASSETS);
        require(onBehalf != address(0), Errors.ZERO_ADDRESS);

        // Don't accrue interest because it's not required and it saves gas.

        collateral[id][onBehalf] += assets;

        emit Events.SupplyCollateral(id, msg.sender, onBehalf, assets);

        if (data.length > 0) IBlueSupplyCollateralCallback(msg.sender).onBlueSupplyCollateral(assets, data);

        IERC20(market.collateralAsset).safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdrawCollateral(Market memory market, uint256 assets, address onBehalf, address receiver) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(assets != 0, Errors.ZERO_ASSETS);
        // No need to verify that onBehalf != address(0) thanks to the authorization check.
        require(receiver != address(0), Errors.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), Errors.UNAUTHORIZED);

        _accrueInterest(market, id);

        collateral[id][onBehalf] -= assets;

        emit Events.WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);

        require(_isHealthy(market, id, onBehalf), Errors.INSUFFICIENT_COLLATERAL);

        IERC20(market.collateralAsset).safeTransfer(receiver, assets);
    }

    // Liquidation.

    function liquidate(Market memory market, address borrower, uint256 seized, bytes calldata data) external {
        Id id = market.id();
        require(lastUpdate[id] != 0, Errors.MARKET_NOT_CREATED);
        require(seized != 0, Errors.ZERO_ASSETS);

        _accrueInterest(market, id);

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        require(!_isHealthy(market, id, borrower, collateralPrice, borrowablePrice), Errors.HEALTHY_POSITION);

        // The liquidation incentive is 1 + ALPHA * (1 / LLTV - 1).
        uint256 incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);
        uint256 repaid = seized.mulWadUp(collateralPrice).divWadUp(incentive).divWadUp(borrowablePrice);
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

        emit Events.Liquidate(id, msg.sender, borrower, repaid, repaidShares, seized, badDebtShares);

        if (data.length > 0) IBlueLiquidateCallback(msg.sender).onBlueLiquidate(seized, repaid, data);

        IERC20(market.borrowableAsset).safeTransferFrom(msg.sender, address(this), repaid);
    }

    // Flash Loans.

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        IERC20(token).safeTransfer(msg.sender, assets);

        emit Events.FlashLoan(msg.sender, token, assets);

        IBlueFlashLoanCallback(msg.sender).onBlueFlashLoan(token, assets, data);

        IERC20(token).safeTransferFrom(msg.sender, address(this), assets);
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

        uint256 usedNonce = nonce[authorizer]++;
        bytes32 hashStruct =
            keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorizer, authorized, newIsAuthorized, usedNonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && authorizer == signatory, Errors.INVALID_SIGNATURE);

        emit Events.IncrementNonce(msg.sender, authorizer, usedNonce);

        isAuthorized[authorizer][authorized] = newIsAuthorized;

        emit Events.SetAuthorization(msg.sender, authorizer, authorized, newIsAuthorized);
    }

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;

        emit Events.SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized);
    }

    function _isSenderAuthorized(address user) internal view returns (bool) {
        return msg.sender == user || isAuthorized[user][msg.sender];
    }

    // Interest management.

    function _accrueInterest(Market memory market, Id id) internal {
        uint256 elapsed = block.timestamp - lastUpdate[id];

        if (elapsed == 0) return;

        uint256 marketTotalBorrow = totalBorrow[id];

        if (marketTotalBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRate(market);
            uint256 interestAccrued = marketTotalBorrow.mulWadDown(borrowRate * elapsed);
            totalBorrow[id] = marketTotalBorrow + interestAccrued;
            totalSupply[id] += interestAccrued;

            uint256 feeShares;
            if (fee[id] != 0) {
                uint256 feeAccrued = interestAccrued.mulWadDown(fee[id]);
                // The accrued fees is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares = feeAccrued.mulDivDown(totalSupplyShares[id], totalSupply[id] - feeAccrued);
                supplyShares[id][feeRecipient] += feeShares;
                totalSupplyShares[id] += feeShares;
            }

            emit Events.AccrueInterest(id, borrowRate, interestAccrued, feeShares);
        }

        lastUpdate[id] = block.timestamp;
    }

    // Health check.

    function _isHealthy(Market memory market, Id id, address user) internal view returns (bool) {
        if (borrowShares[id][user] == 0) return true;

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        return _isHealthy(market, id, user, collateralPrice, borrowablePrice);
    }

    function _isHealthy(Market memory market, Id id, address user, uint256 collateralPrice, uint256 borrowablePrice)
        internal
        view
        returns (bool)
    {
        uint256 borrowValue =
            borrowShares[id][user].toAssetsUp(totalBorrow[id], totalBorrowShares[id]).mulWadUp(borrowablePrice);
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
