// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/*
 * MORPHO BLUE -- UNVERIFIED RECONSTRUCTION FROM MEMORY
 *
 * This is NOT the official Morpho Blue source, a verbatim transcription, or
 * a copy of any identified commit. No internet sources were consulted.
 *
 * Scope: a best-effort reconstruction of the core lending contract, including
 * its data model, market administration, lending, collateral, liquidation,
 * flash loans, authorization, and interest accrual.
 *
 * Deliberate differences / areas of uncertainty:
 * - The contract and helper libraries have new names and are flattened here.
 * - Imports, interfaces, comments, license metadata, and file layout are not
 *   reproduced from the original repository. UNLICENSED applies to this
 *   reconstruction's distribution; it is not a claim about Morpho's license.
 * - Event indexing, revert strings, declaration order, and some validation
 *   details are reconstructed and may differ from the original.
 * - Arithmetic and ERC-20 helpers below are handwritten replacements.
 * - Constants, rounding, callback order, signature handling, and accounting
 *   are recalled from memory and have not been checked against the original.
 * - This does not include Morpho's separate IRM implementations, periphery,
 *   tests, deployment configuration, or complete interface/library repository.
 *
 * Verification: no Solidity compiler was available when this was written.
 * This file is uncompiled and unaudited; source or bytecode equivalence has
 * not been established. It is for inspection, not deployment with funds.
 */

type Id is bytes32;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IReconstructedOracle {
    function price() external view returns (uint256);
}

interface IReconstructedIrm {
    function borrowRate(MarketParams memory marketParams, Market memory market)
        external
        returns (uint256);
}

interface IReconstructedSupplyCallback {
    function onMorphoSupply(uint256 assets, bytes calldata data) external;
}

interface IReconstructedRepayCallback {
    function onMorphoRepay(uint256 assets, bytes calldata data) external;
}

interface IReconstructedSupplyCollateralCallback {
    function onMorphoSupplyCollateral(uint256 assets, bytes calldata data) external;
}

interface IReconstructedLiquidateCallback {
    function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external;
}

interface IReconstructedFlashLoanCallback {
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

// These helpers implement recalled behavior; their source is newly written.
library ReconstructedMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x - y : 0;
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "uint128 overflow");
        return uint128(x);
    }

    // These use checked 256-bit multiplication, not 512-bit mulDiv.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return x * y / d;
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        uint256 product = x * y;
        return product / d + (product % d == 0 ? 0 : 1);
    }

    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    function wDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    function wTaylorCompounded(uint256 rate, uint256 elapsed) internal pure returns (uint256) {
        uint256 firstTerm = rate * elapsed;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);
        return firstTerm + secondTerm + thirdTerm;
    }

    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares)
        internal pure returns (uint256)
    {
        return mulDivDown(assets, totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares)
        internal pure returns (uint256)
    {
        return mulDivUp(assets, totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares)
        internal pure returns (uint256)
    {
        return mulDivDown(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares)
        internal pure returns (uint256)
    {
        return mulDivUp(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }
}

library ReconstructedTokenTransfers {
    function safeTransfer(address token, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSelector(bytes4(0xa9059cbb), to, amount));
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSelector(bytes4(0x23b872dd), from, to, amount));
    }

    function _call(address token, bytes memory data) private {
        require(token.code.length != 0, "token has no code");
        (bool success, bytes memory result) = token.call(data);
        require(success, "token call failed");
        require(result.length == 0 || abi.decode(result, (bool)), "token returned false");
    }
}

contract MorphoBlueReconstruction {
    using ReconstructedMath for uint256;
    using ReconstructedTokenTransfers for address;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
    uint256 internal constant MAX_FEE = 0.25e18;
    uint256 internal constant LIQUIDATION_CURSOR = 0.3e18;
    uint256 internal constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 internal constant AUTHORIZATION_TYPEHASH = keccak256(
        "Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;
    address public owner;
    address public feeRecipient;

    mapping(Id => mapping(address => Position)) public position;
    mapping(Id => Market) public market;
    mapping(address => bool) public isIrmEnabled;
    mapping(uint256 => bool) public isLltvEnabled;
    mapping(address => mapping(address => bool)) public isAuthorized;
    mapping(address => uint256) public nonce;
    mapping(Id => MarketParams) public idToMarketParams;

    // Event names and values are recalled; indexing is unverified.
    event SetOwner(address indexed newOwner);
    event EnableIrm(address indexed irm);
    event EnableLltv(uint256 lltv);
    event SetFee(Id indexed id, uint256 newFee);
    event SetFeeRecipient(address indexed newFeeRecipient);
    event CreateMarket(Id indexed id, MarketParams marketParams);
    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver,
        uint256 assets, uint256 shares
    );
    event Borrow(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver,
        uint256 assets, uint256 shares
    );
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event SupplyCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets);
    event WithdrawCollateral(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver, uint256 assets
    );
    event Liquidate(
        Id indexed id, address indexed caller, address indexed borrower, uint256 repaidAssets,
        uint256 repaidShares, uint256 seizedAssets, uint256 badDebtAssets, uint256 badDebtShares
    );
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);
    event SetAuthorization(
        address indexed caller, address indexed authorizer, address indexed authorized, bool newIsAuthorized
    );
    event IncrementNonce(address indexed caller, address indexed authorizer, uint256 usedNonce);
    event AccrueInterest(Id indexed id, uint256 borrowRate, uint256 interest, uint256 feeShares);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address newOwner) {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        emit SetOwner(newOwner);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != owner, "already set");
        owner = newOwner;
        emit SetOwner(newOwner);
    }

    function enableIrm(address irm) external onlyOwner {
        require(!isIrmEnabled[irm], "already enabled");
        isIrmEnabled[irm] = true;
        emit EnableIrm(irm);
    }

    function enableLltv(uint256 lltv) external onlyOwner {
        require(!isLltvEnabled[lltv], "already enabled");
        require(lltv < WAD, "max lltv exceeded");
        isLltvEnabled[lltv] = true;
        emit EnableLltv(lltv);
    }

    function setFee(MarketParams memory marketParams, uint256 newFee) external onlyOwner {
        Id id = _id(marketParams);
        _requireMarket(id);
        require(newFee != market[id].fee, "already set");
        require(newFee <= MAX_FEE, "max fee exceeded");
        _accrueInterest(marketParams, id);
        market[id].fee = newFee.toUint128();
        emit SetFee(id, newFee);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != feeRecipient, "already set");
        feeRecipient = newFeeRecipient;
        emit SetFeeRecipient(newFeeRecipient);
    }

    function createMarket(MarketParams memory marketParams) external {
        Id id = _id(marketParams);
        require(isIrmEnabled[marketParams.irm], "irm not enabled");
        require(isLltvEnabled[marketParams.lltv], "lltv not enabled");
        require(market[id].lastUpdate == 0, "market already created");

        market[id].lastUpdate = block.timestamp.toUint128();
        idToMarketParams[id] = marketParams;
        emit CreateMarket(id, marketParams);

        if (marketParams.irm != address(0)) {
            IReconstructedIrm(marketParams.irm).borrowRate(marketParams, market[id]);
        }
    }

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256) {
        Id id = _id(marketParams);
        _requireMarket(id);
        _requireExactlyOneZero(assets, shares);
        require(onBehalf != address(0), "zero address");
        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesDown(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        } else {
            assets = shares.toAssetsUp(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        }

        position[id][onBehalf].supplyShares += shares;
        market[id].totalSupplyShares += shares.toUint128();
        market[id].totalSupplyAssets += assets.toUint128();
        emit Supply(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IReconstructedSupplyCallback(msg.sender).onMorphoSupply(assets, data);
        marketParams.loanToken.safeTransferFrom(msg.sender, address(this), assets);
        return (assets, shares);
    }

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        Id id = _id(marketParams);
        _requireMarket(id);
        _requireExactlyOneZero(assets, shares);
        require(receiver != address(0), "zero address");
        require(_isSenderAuthorized(onBehalf), "unauthorized");
        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesUp(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        } else {
            assets = shares.toAssetsDown(market[id].totalSupplyAssets, market[id].totalSupplyShares);
        }

        position[id][onBehalf].supplyShares -= shares;
        market[id].totalSupplyShares -= shares.toUint128();
        market[id].totalSupplyAssets -= assets.toUint128();
        require(market[id].totalBorrowAssets <= market[id].totalSupplyAssets, "insufficient liquidity");
        emit Withdraw(id, msg.sender, onBehalf, receiver, assets, shares);
        marketParams.loanToken.safeTransfer(receiver, assets);
        return (assets, shares);
    }

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        Id id = _id(marketParams);
        _requireMarket(id);
        _requireExactlyOneZero(assets, shares);
        require(receiver != address(0), "zero address");
        require(_isSenderAuthorized(onBehalf), "unauthorized");
        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        } else {
            assets = shares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        }

        position[id][onBehalf].borrowShares += shares.toUint128();
        market[id].totalBorrowShares += shares.toUint128();
        market[id].totalBorrowAssets += assets.toUint128();
        require(_isHealthy(marketParams, id, onBehalf), "insufficient collateral");
        require(market[id].totalBorrowAssets <= market[id].totalSupplyAssets, "insufficient liquidity");
        emit Borrow(id, msg.sender, onBehalf, receiver, assets, shares);
        marketParams.loanToken.safeTransfer(receiver, assets);
        return (assets, shares);
    }

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256) {
        Id id = _id(marketParams);
        _requireMarket(id);
        _requireExactlyOneZero(assets, shares);
        require(onBehalf != address(0), "zero address");
        _accrueInterest(marketParams, id);

        if (assets > 0) {
            shares = assets.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        } else {
            assets = shares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        }

        position[id][onBehalf].borrowShares -= shares.toUint128();
        market[id].totalBorrowShares -= shares.toUint128();
        market[id].totalBorrowAssets = uint256(market[id].totalBorrowAssets).zeroFloorSub(assets).toUint128();
        emit Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IReconstructedRepayCallback(msg.sender).onMorphoRepay(assets, data);
        marketParams.loanToken.safeTransferFrom(msg.sender, address(this), assets);
        return (assets, shares);
    }

    function supplyCollateral(
        MarketParams memory marketParams, uint256 assets, address onBehalf, bytes calldata data
    ) external {
        Id id = _id(marketParams);
        _requireMarket(id);
        require(assets != 0, "zero assets");
        require(onBehalf != address(0), "zero address");

        position[id][onBehalf].collateral += assets.toUint128();
        emit SupplyCollateral(id, msg.sender, onBehalf, assets);
        if (data.length > 0) {
            IReconstructedSupplyCollateralCallback(msg.sender).onMorphoSupplyCollateral(assets, data);
        }
        marketParams.collateralToken.safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdrawCollateral(
        MarketParams memory marketParams, uint256 assets, address onBehalf, address receiver
    ) external {
        Id id = _id(marketParams);
        _requireMarket(id);
        require(assets != 0, "zero assets");
        require(receiver != address(0), "zero address");
        require(_isSenderAuthorized(onBehalf), "unauthorized");
        _accrueInterest(marketParams, id);

        position[id][onBehalf].collateral -= assets.toUint128();
        require(_isHealthy(marketParams, id, onBehalf), "insufficient collateral");
        emit WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets);
        marketParams.collateralToken.safeTransfer(receiver, assets);
    }

    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256, uint256) {
        Id id = _id(marketParams);
        _requireMarket(id);
        _requireExactlyOneZero(seizedAssets, repaidShares);
        _accrueInterest(marketParams, id);

        {
            uint256 collateralPrice = IReconstructedOracle(marketParams.oracle).price();
            require(!_isHealthy(marketParams, id, borrower, collateralPrice), "healthy position");

            uint256 liquidationIncentiveFactor = ReconstructedMath.min(
                MAX_LIQUIDATION_INCENTIVE_FACTOR,
                WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - marketParams.lltv))
            );

            if (seizedAssets > 0) {
                uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
                repaidShares = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor).toSharesUp(
                    market[id].totalBorrowAssets, market[id].totalBorrowShares
                );
            } else {
                seizedAssets = repaidShares.toAssetsDown(
                    market[id].totalBorrowAssets, market[id].totalBorrowShares
                ).wMulDown(liquidationIncentiveFactor).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
            }
        }

        uint256 repaidAssets = repaidShares.toAssetsUp(
            market[id].totalBorrowAssets, market[id].totalBorrowShares
        );

        position[id][borrower].borrowShares -= repaidShares.toUint128();
        market[id].totalBorrowShares -= repaidShares.toUint128();
        market[id].totalBorrowAssets = uint256(market[id].totalBorrowAssets)
            .zeroFloorSub(repaidAssets).toUint128();
        position[id][borrower].collateral -= seizedAssets.toUint128();

        uint256 badDebtShares;
        uint256 badDebtAssets;

        if (position[id][borrower].collateral == 0) {
            badDebtShares = position[id][borrower].borrowShares;
            badDebtAssets = ReconstructedMath.min(
                market[id].totalBorrowAssets,
                badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares)
            );

            market[id].totalBorrowAssets -= badDebtAssets.toUint128();
            market[id].totalSupplyAssets -= badDebtAssets.toUint128();
            market[id].totalBorrowShares -= badDebtShares.toUint128();
            position[id][borrower].borrowShares = 0;
        }

        emit Liquidate(
            id, msg.sender, borrower, repaidAssets, repaidShares, seizedAssets, badDebtAssets, badDebtShares
        );

        marketParams.collateralToken.safeTransfer(msg.sender, seizedAssets);
        if (data.length > 0) {
            IReconstructedLiquidateCallback(msg.sender).onMorphoLiquidate(repaidAssets, data);
        }
        marketParams.loanToken.safeTransferFrom(msg.sender, address(this), repaidAssets);
        return (seizedAssets, repaidAssets);
    }

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        require(assets != 0, "zero assets");
        emit FlashLoan(msg.sender, token, assets);
        token.safeTransfer(msg.sender, assets);
        IReconstructedFlashLoanCallback(msg.sender).onMorphoFlashLoan(assets, data);
        token.safeTransferFrom(msg.sender, address(this), assets);
    }

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        require(isAuthorized[msg.sender][authorized] != newIsAuthorized, "already set");
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
        emit SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized);
    }

    function setAuthorizationWithSig(Authorization memory authorization, Signature calldata signature)
        external
    {
        require(block.timestamp <= authorization.deadline, "signature expired");
        require(authorization.nonce == nonce[authorization.authorizer]++, "invalid nonce");

        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
        require(signatory != address(0) && signatory == authorization.authorizer, "invalid signature");

        emit IncrementNonce(msg.sender, authorization.authorizer, authorization.nonce);
        isAuthorized[authorization.authorizer][authorization.authorized] = authorization.isAuthorized;
        emit SetAuthorization(
            msg.sender, authorization.authorizer, authorization.authorized, authorization.isAuthorized
        );
    }

    function accrueInterest(MarketParams memory marketParams) external {
        Id id = _id(marketParams);
        _requireMarket(id);
        _accrueInterest(marketParams, id);
    }

    function extSloads(bytes32[] calldata slots) external view returns (bytes32[] memory res) {
        res = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) {
            bytes32 slot = slots[i];
            bytes32 value;
            assembly {
                value := sload(slot)
            }
            res[i] = value;
        }
    }

    function _accrueInterest(MarketParams memory marketParams, Id id) internal {
        uint256 elapsed = block.timestamp - market[id].lastUpdate;
        if (elapsed == 0) return;

        if (marketParams.irm != address(0)) {
            uint256 borrowRate = IReconstructedIrm(marketParams.irm).borrowRate(marketParams, market[id]);
            uint256 interest = uint256(market[id].totalBorrowAssets)
                .wMulDown(borrowRate.wTaylorCompounded(elapsed));

            market[id].totalBorrowAssets += interest.toUint128();
            market[id].totalSupplyAssets += interest.toUint128();

            uint256 feeShares;
            if (market[id].fee != 0) {
                uint256 feeAmount = interest.wMulDown(market[id].fee);
                feeShares = feeAmount.toSharesDown(
                    market[id].totalSupplyAssets - feeAmount, market[id].totalSupplyShares
                );
                position[id][feeRecipient].supplyShares += feeShares;
                market[id].totalSupplyShares += feeShares.toUint128();
            }

            emit AccrueInterest(id, borrowRate, interest, feeShares);
        }

        market[id].lastUpdate = block.timestamp.toUint128();
    }

    function _isHealthy(MarketParams memory marketParams, Id id, address borrower)
        internal view returns (bool)
    {
        if (position[id][borrower].borrowShares == 0) return true;
        uint256 collateralPrice = IReconstructedOracle(marketParams.oracle).price();
        return _isHealthy(marketParams, id, borrower, collateralPrice);
    }

    function _isHealthy(MarketParams memory marketParams, Id id, address borrower, uint256 collateralPrice)
        internal view returns (bool)
    {
        uint256 borrowed = uint256(position[id][borrower].borrowShares).toAssetsUp(
            market[id].totalBorrowAssets, market[id].totalBorrowShares
        );
        uint256 maxBorrow = uint256(position[id][borrower].collateral)
            .mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);
        return maxBorrow >= borrowed;
    }

    function _isSenderAuthorized(address onBehalf) internal view returns (bool) {
        return msg.sender == onBehalf || isAuthorized[onBehalf][msg.sender];
    }

    function _id(MarketParams memory marketParams) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams)));
    }

    function _requireMarket(Id id) internal view {
        require(market[id].lastUpdate != 0, "market not created");
    }

    function _requireExactlyOneZero(uint256 x, uint256 y) internal pure {
        require((x == 0) != (y == 0), "inconsistent input");
    }
}
