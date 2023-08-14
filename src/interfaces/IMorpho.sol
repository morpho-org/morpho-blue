// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IFlashLender} from "./IFlashLender.sol";

type Id is bytes32;

/// @notice Contains the parameters defining market.
/// @param borrowableToken The address of the borrowable token.
/// @param collateralToken The address of the collateral token.
/// @param oracle The address of the oracle.
/// @param irm The address of the interest rate model.
/// @param lltv The Liquidation LTV.
struct Market {
    address borrowableToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

/// @notice Authorization struct.
/// @param authorizer Authorizer address.
/// @param authorized Authorized address.
/// @param isAuthorized The authorization status to set.
/// @param nonce Signature nonce.
/// @param deadline Signature deadline.
struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @title IMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface of Morpho.
interface IMorpho is IFlashLender {
    /// @notice The EIP-712 domain separator.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The owner of the contract.
    function owner() external view returns (address);

    /// @notice The fee recipient.
    /// @dev The recipient receives the fees through a supply position.
    function feeRecipient() external view returns (address);

    /// @notice The `user`'s supply shares on the market `id`.
    function supplyShares(Id id, address user) external view returns (uint256);

    /// @notice The `user`'s borrow shares on the market `id`.
    function borrowShares(Id, address user) external view returns (uint256);

    /// @notice The `user`'s collateral balance on the market `id`.
    function collateral(Id id, address user) external view returns (uint256);

    /// @notice The total supply of the market `id`.
    /// @dev Does not contain the accrued interest since the last interaction.
    function totalSupply(Id id) external view returns (uint256);

    /// @notice The total supply shares of the market `id`.
    function totalSupplyShares(Id id) external view returns (uint256);

    /// @notice The total borrow of the market `id`.
    /// @dev Does not contain the accrued interest since the last interaction.
    function totalBorrow(Id id) external view returns (uint256);

    /// @notice The total borrow shares of the market `id`.
    function totalBorrowShares(Id id) external view returns (uint256);

    /// @notice The last update timestamp of the market `id` (also used to check if a market has been created).
    function lastUpdate(Id id) external view returns (uint256);

    /// @notice The fee of the market `id`.
    function fee(Id id) external view returns (uint256);

    /// @notice Whether the `irm` is enabled.
    function isIrmEnabled(address irm) external view returns (bool);

    /// @notice Whether the `lltv` is enabled.
    function isLltvEnabled(uint256 lltv) external view returns (bool);

    /// @notice Whether `authorized` is authorized to modify `authorizer`'s positions.
    /// @dev Anyone is authorized to modify their own positions, regardless of this variable.
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

    /// @notice Supplies the given `assets` or `shares` to the given `market` on behalf of `onBehalf`,
    ///         optionally calling back the caller's `onMorphoSupply` function with the given `data`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      Most usecases should rely on `assets` as an input so the caller
    ///      is guaranteed to have `assets` tokens pulled from their balance,
    ///      but the possibility to mint a specific amount of shares is given
    ///      for full compatibility and precision.
    /// @dev Supplying a large amount can overflow and revert without any error message.
    /// @param market The market to supply assets to.
    /// @param assets The amount of assets to supply.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address that will receive the position.
    /// @param data Arbitrary data to pass to the `onMorphoSupply` callback. Pass empty data if not needed.
    /// @return assetsSupplied The amount of assets supplied.
    /// @return sharesSupplied The amount of shares supplied.
    function supply(Market memory market, uint256 assets, uint256 shares, address onBehalf, bytes memory data)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied);

    /// @notice Withdraws the given `assets` or `shares` from the given `market` on behalf of `onBehalf`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      To withdraw the whole position, pass the `shares`'s balance of `onBehalf`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Withdrawing an amount corresponding to more shares than supplied will underflow and revert without any error message.
    /// @param market The market to withdraw assets from.
    /// @param assets The amount of assets to withdraw.
    /// @param shares The amount of shares to burn.
    /// @param onBehalf The address of the owner of the withdrawn assets.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @return assetsWithdrawn The amount of assets withdrawn.
    /// @return sharesWithdrawn The amount of shares withdrawn.
    function withdraw(Market memory market, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    /// @notice Borrows the given `assets` or `shares` from the given `market` on behalf of `onBehalf`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      Most usecases should rely on `assets` as an input so the caller
    ///      is guaranteed to borrow `assets` of tokens,
    ///      but the possibility to burn a specific amount of shares is given
    ///      for full compatibility and precision.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Borrowing a large amount can overflow and revert without any error message.
    /// @param market The market to borrow assets from.
    /// @param assets The amount of assets to borrow.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address of the owner of the debt.
    /// @param receiver The address that will receive the debt.
    /// @return assetsBorrowed The amount of assets borrowed.
    /// @return sharesBorrowed The amount of shares borrowed.
    function borrow(Market memory market, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    /// @notice Repays the given `assets` or `shares` to the given `market` on behalf of `onBehalf`,
    ///         optionally calling back the caller's `onMorphoReplay` function with the given `data`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      To repay the whole debt, pass the `shares`'s balance of `onBehalf`.
    /// @dev Repaying an amount corresponding to more shares than borrowed will underflow and revert without any error message.
    /// @param market The market to repay assets to.
    /// @param assets The amount of assets to repay.
    /// @param shares The amount of shares to burn.
    /// @param onBehalf The address of the owner of the debt.
    /// @param data Arbitrary data to pass to the `onMorphoRepay` callback. Pass empty data if not needed.
    /// @return assetsRepaid The amount of assets repaid.
    /// @return sharesRepaid The amount of shares repaid.
    function repay(Market memory market, uint256 assets, uint256 shares, address onBehalf, bytes memory data)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Supplies the given `assets` of collateral to the given `market` on behalf of `onBehalf`,
    ///         optionally calling back the caller's `onMorphoSupplyCollateral` function with the given `data`.
    /// @dev Interests are not accrued since it's not required and it saves gas.
    /// @dev Supplying a large amount can overflow and revert without any error message.
    /// @param market The market to supply collateral to.
    /// @param assets The assets of collateral to supply.
    /// @param onBehalf The address that will receive the collateral.
    /// @param data Arbitrary data to pass to the `onMorphoSupplyCollateral` callback. Pass empty data if not needed.
    function supplyCollateral(Market memory market, uint256 assets, address onBehalf, bytes memory data) external;

    /// @notice Withdraws the given `assets` of collateral from the given `market` on behalf of `onBehalf`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Withdrawing an amount corresponding to more collateral than supplied will underflow and revert without any error message.
    /// @param market The market to withdraw collateral from.
    /// @param assets The assets of collateral to withdraw.
    /// @param onBehalf The address of the owner of the collateral.
    /// @param receiver The address that will receive the withdrawn collateral.
    function withdrawCollateral(Market memory market, uint256 assets, address onBehalf, address receiver) external;

    /// @notice Liquidates the given `seized` assets to the given `market` of the given `borrower`'s position,
    ///         optionally calling back the caller's `onMorphoLiquidate` function with the given `data`.
    /// @dev Seizing more than the collateral balance will underflow and revert without any error message.
    /// @dev Repaying more than the borrow balance will underflow and revert without any error message.
    /// @param market The market of the position.
    /// @param borrower The owner of the position.
    /// @param seized The assets of collateral to seize.
    /// @param data Arbitrary data to pass to the `onMorphoLiquidate` callback. Pass empty data if not needed.
    /// @return assetsRepaid The amount of assets repaid.
    /// @return sharesRepaid The amount of shares repaid.
    function liquidate(Market memory market, address borrower, uint256 seized, bytes memory data)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Sets the authorization for `authorized` to manage `msg.sender`'s positions.
    /// @param authorized The authorized address.
    /// @param newIsAuthorized The new authorization status.
    function setAuthorization(address authorized, bool newIsAuthorized) external;

    /// @notice Sets the authorization for `authorization.authorized` to manage `authorization.authorizer`'s positions.
    /// @param authorization The `Authorization` struct.
    /// @param signature The signature.
    function setAuthorizationWithSig(Authorization calldata authorization, Signature calldata signature) external;

    /// @notice Accrues interests for `market`.
    function accrueInterests(Market memory market) external;

    /// @notice Returns the data stored on the different `slots`.
    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory res);
}
