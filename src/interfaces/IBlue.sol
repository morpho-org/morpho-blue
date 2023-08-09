// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IFlashLender} from "./IFlashLender.sol";

type Id is bytes32;

struct Market {
    address borrowableAsset;
    address collateralAsset;
    address borrowableOracle;
    address collateralOracle;
    address irm;
    uint256 lltv;
}

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @title IBlue
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface of Blue.
interface IBlue is IFlashLender {
    /// @notice Emitted when setting a new owner.
    /// @param newOwner The new owner of the contract.
    event SetOwner(address indexed newOwner);

    /// @notice Emitted when setting a new fee.
    /// @param id The market id.
    /// @param fee The new fee.
    event SetFee(Id indexed id, uint256 fee);

    /// @notice Emitted when setting a new fee recipient.
    /// @param feeRecipient The new fee recipient.
    event SetFeeRecipient(address indexed feeRecipient);

    /// @notice Emitted when enabling an IRM.
    /// @param irm The IRM that was enabled.
    event EnableIrm(address indexed irm);

    /// @notice Emitted when enabling an LLTV.
    /// @param lltv The LLTV that was enabled.
    event EnableLltv(uint256 lltv);

    /// @notice Emitted when creating a market.
    /// @param id The market id.
    /// @param market The market that was created.
    event CreateMarket(Id indexed id, Market market);

    /// @notice Emitted on supply of assets.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The address that will receive the position.
    /// @param amount The amount of assets supplied.
    /// @param shares The amount of shares minted.
    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);

    /// @notice Emitted on withdrawal of assets.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The address from which the assets are withdrawn.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @param amount The amount of assets withdrawn.
    /// @param shares The amount of shares burned.
    event Withdraw(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted on borrow of assets.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The address from which the assets are borrowed.
    /// @param receiver The address that will receive the borrowed assets.
    /// @param amount The amount of assets borrowed.
    /// @param shares The amount of shares minted.
    event Borrow(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted on repayment of assets.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The address for which the assets are repaid.
    /// @param amount The amount of assets repaid.
    /// @param shares The amount of shares burned.
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);

    /// @notice Emitted on supply of collateral.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The address that will receive the position.
    /// @param amount The amount of collateral supplied.
    event SupplyCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount);

    /// @notice Emitted on withdrawal of collateral.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The address from which the collateral is withdrawn.
    /// @param receiver The address that will receive the withdrawn collateral.
    /// @param amount The amount of collateral withdrawn.
    event WithdrawCollateral(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver, uint256 amount
    );

    /// @notice Emitted on liquidation of a position.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param borrower The borrower of the position.
    /// @param repaid The amount of assets repaid.
    /// @param repaidShares The amount of shares burned.
    /// @param seized The amount of collateral seized.
    /// @param badDebtShares The amount of shares minted as bad debt.
    event Liquidate(
        Id indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaid,
        uint256 repaidShares,
        uint256 seized,
        uint256 badDebtShares
    );

    /// @notice Emitted on flash loan.
    /// @param caller The caller..
    /// @param token The token that was flash loaned.
    /// @param amount The amount that was flash loaned.
    event FlashLoan(address indexed caller, address indexed token, uint256 amount);

    /// @notice Emitted when setting an authorization.
    /// @param caller The caller.
    /// @param authorizer The authorizer address.
    /// @param authorized The authorized address.
    /// @param newIsAuthorized The new authorization status.
    event SetAuthorization(
        address indexed caller, address indexed authorizer, address indexed authorized, bool newIsAuthorized
    );

    /// @notice Emitted when setting an authorization with a signature.
    /// @param caller The caller.
    /// @param authorizer The authorizer address.
    /// @param usedNonce The nonce that was used.
    event IncrementNonce(address indexed caller, address indexed authorizer, uint256 usedNonce);

    /// @notice Emitted when accruing interests.
    /// @param id The market id.
    /// @param prevBorrowRate The previous borrow rate.
    /// @param accruedInterests The amount of interests accrued.
    /// @param feeShares The amount of shares minted as fee.
    event AccrueInterests(Id indexed id, uint256 prevBorrowRate, uint256 accruedInterests, uint256 feeShares);

    /// @notice The EIP-712 domain separator.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The owner of the contract.
    function owner() external view returns (address);

    /// @notice The fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice The `user`'s supply shares on the market defined by the given `id`.
    function supplyShares(Id id, address user) external view returns (uint256);

    /// @notice The `user`'s borrow shares on the market defined by the given `id`.
    function borrowShares(Id, address user) external view returns (uint256);

    /// @notice The `user`'s collateral balance on the market defined by the given `id`.
    function collateral(Id id, address user) external view returns (uint256);

    /// @notice The total amount of assets supplied to the market defined by the given `id`.
    /// @dev The value can be incaccurate since it does not take into account the accrued interests.
    function totalSupply(Id id) external view returns (uint256);

    /// @notice The total supply shares of the market defined by the given `id`.
    function totalSupplyShares(Id id) external view returns (uint256);

    /// @notice The total amount of assets borrowed from the market defined by the given `id`.
    /// @dev The value can be incaccurate since it does not take into account the accrued interests.
    function totalBorrow(Id id) external view returns (uint256);

    /// @notice The total borrow shares of the market defined by the given `id`.
    function totalBorrowShares(Id id) external view returns (uint256);

    /// @notice The last update of the market defined by the given `id` (used to check if a market has been created).
    function lastUpdate(Id id) external view returns (uint256);

    /// @notice The fee of the market defined by the given `id`.
    function fee(Id id) external view returns (uint256);

    /// @notice Whether the `irm` is enabled.
    function isIrmEnabled(address irm) external view returns (bool);

    /// @notice Whether the `lltv` is enabled.
    function isLltvEnabled(uint256 lltv) external view returns (bool);

    /// @notice Whether `aurothized` is authorized to modify `authorizer`'s positions.
    /// @dev By default, `msg.sender` is authorized by themself.
    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    /// @notice The `user`'s current nonce. Used to prevent replay attacks with EIP-712 signatures.
    function nonce(address user) external view returns (uint256);

    /// @notice Sets `newOwner` as owner of the contract.
    function setOwner(address newOwner) external;

    /// @notice Enables `irm` as possible IRM for market creation.
    function enableIrm(address irm) external;

    /// @notice Enables `lltv` as possible LLTV for market creation.
    function enableLltv(uint256 lltv) external;

    /// @notice Sets the `newFee` for `market`.
    /// @dev It is the `owner`'s responsibility to ensure `feeRecipient` is set before setting a non-zero fee.
    function setFee(Market memory market, uint256 newFee) external;

    /// @notice Sets `recipient` as recipient of the fee.
    function setFeeRecipient(address recipient) external;

    /// @notice Creates `market`.
    function createMarket(Market memory market) external;

    /// @notice Supplies assets to a market.
    /// @param market The market to supply assets to.
    /// @param amount The amount of assets to supply.
    /// @param onBehalf The address that will receive the position.
    /// @param data Arbitrary data to pass to the `onBlueSupply` callback. Pass empty data if not needed.
    function supply(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;

    /// @notice Withdraws assets from a market.
    /// @param market The market to withdraw assets from.
    /// @param onBehalf The address from which to withdraw.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @dev If `msg.sender != onBehalf`, `msg.sender` must be authorized to withdraw from `onBehalf`.
    function withdraw(Market memory market, uint256 amount, address onBehalf, address receiver) external;

    /// @notice Borrows assets from a market.
    /// @param market The market to borrow assets from.
    /// @param amount The amount of assets to borrow.
    /// @param onBehalf The address from which to borrow.
    /// @param receiver The address that will receive the borrowed assets.
    /// @dev If `msg.sender != onBehalf`, `msg.sender` must be authorized to withdraw from `onBehalf`.
    function borrow(Market memory market, uint256 amount, address onBehalf, address receiver) external;

    /// @notice Repays assets to a market.
    /// @param market The market to repay assets to.
    /// @param onBehalf The address for which to repay.
    /// @param data Arbitrary data to pass to the `onBlueRepay` callback. Pass empty data if not needed.
    function repay(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;

    /// @notice Supplies collateral to a market.
    /// @param market The market to supply collateral to.
    /// @param amount The amount of collateral to supply.
    /// @param onBehalf The address that will receive the position.
    /// @param data Arbitrary data to pass to the `onBlueSupplyCollateral` callback. Pass empty data if not needed.
    /// @dev Don't accrue interests because it's not required and it saves gas.
    function supplyCollateral(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;

    /// @notice Withdraws collateral from a market.
    /// @param market The market to withdraw collateral from.
    /// @param amount The amount of collateral to withdraw.
    /// @param onBehalf The address from which to withdraw.
    /// @param receiver The address that will receive the withdrawn collateral.
    /// @dev If `msg.sender != onBehalf`, `msg.sender` must be authorized to withdraw from `onBehalf`.
    function withdrawCollateral(Market memory market, uint256 amount, address onBehalf, address receiver) external;

    /// @notice Liquidates a position.
    /// @param market The market of the position.
    /// @param borrower The borrower of the position.
    /// @param seized The amount of collateral to seize.
    /// @param data Arbitrary data to pass to the `onBlueLiquidate` callback. Pass empty data if not needed
    function liquidate(Market memory market, address borrower, uint256 seized, bytes memory data) external;

    /// @notice Sets the authorization for `authorized` to manage `msg.sender`'s positions.
    /// @param authorized The authorized address.
    /// @param newIsAuthorized The new authorization status.
    function setAuthorization(address authorized, bool newIsAuthorized) external;

    /// @notice Sets the authorization for `authorized` to manage `authorizer`'s positions.
    /// @param authorizer The authorizer address.
    /// @param authorized The authorized address.
    /// @param newIsAuthorized The new authorization status.
    /// @param deadline The deadline after which the signature is invalid.
    /// @dev The signature is malleable, but it has no impact on the security here.
    function setAuthorization(
        address authorizer,
        address authorized,
        bool newIsAuthorized,
        uint256 deadline,
        Signature calldata signature
    ) external;

    /// @notice Returns the data stored on the different `slots`.
    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory res);
}
