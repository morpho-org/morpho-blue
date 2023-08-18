// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

type Id is bytes32;

struct Config {
    address borrowableToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

struct User {
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

/// @title IMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interface of Morpho.
interface IMorpho {
    /// @notice The EIP-712 domain separator.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The owner of the contract.
    function owner() external view returns (address);

    /// @notice The fee recipient.
    /// @dev The recipient receives the fees through a supply position.
    function feeRecipient() external view returns (address);

    /// @notice Users' storage for market `id`.
    /// @dev Warning: supplyShares does not contain the accrued shares since the last interaction for `feeRecipient`.
    function user(Id id, address user) external view returns (uint256, uint128, uint128);

    /// @notice Market storage for market `id`.
    /// @dev Warning: totalSupplyAssets does not contain the accrued interest since the last interaction.
    /// @dev Warning: totalBorrowAssets does not contain the accrued interest since the last interaction.
    /// @dev Warning: totalSupplyShares does not contain the additionnal shares accrued by `feeRecipient` since the last interaction.
    function market(Id id) external view returns (uint128, uint128, uint128, uint128, uint128, uint128);

    /// @notice Whether the `irm` is enabled.
    function isIrmEnabled(address irm) external view returns (bool);

    /// @notice Whether the `lltv` is enabled.
    function isLltvEnabled(uint256 lltv) external view returns (bool);

    /// @notice Whether `authorized` is authorized to modify `authorizer`'s positions.
    /// @dev Anyone is authorized to modify their own positions, regardless of this variable.
    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    /// @notice The `user`'s current nonce. Used to prevent replay attacks with EIP-712 signatures.
    function nonce(address user) external view returns (uint256);

    /// @notice The market configuration corresponding to `id`.
    function idToConfig(Id id)
        external
        view
        returns (address borrowableAsset, address collateralAsset, address oracle, address irm, uint256 lltv);

    /// @notice Sets `newOwner` as owner of the contract.
    /// @dev Warning: No two-step transfer ownership.
    /// @dev Warning: The owner can be set to the zero address.
    function setOwner(address newOwner) external;

    /// @notice Enables `irm` as possible IRM for market creation.
    /// @dev Warning: It is not possible to disable an IRM.
    function enableIrm(address irm) external;

    /// @notice Enables `lltv` as possible LLTV for market creation.
    /// @dev Warning: It is not possible to disable a LLTV.
    function enableLltv(uint256 lltv) external;

    /// @notice Sets the `newFee` for `market`.
    /// @dev Warning: The recipient can be the zero address.
    function setFee(Config memory config, uint256 newFee) external;

    /// @notice Sets `recipient` as recipient of the fee.
    /// @dev Warning: The recipient can be set to the zero address.
    function setFeeRecipient(address recipient) external;

    /// @notice Creates `market`.
    function createMarket(Config memory config) external;

    /// @notice Supplies the given `assets` or `shares` to the given `market` on behalf of `onBehalf`,
    ///         optionally calling back the caller's `onMorphoSupply` function with the given `data`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      Most usecases should rely on `assets` as an input so the caller
    ///      is guaranteed to have `assets` tokens pulled from their balance,
    ///      but the possibility to mint a specific amount of shares is given
    ///      for full compatibility and precision.
    /// @dev Supplying a large amount can overflow and revert without any error message.
    /// @param config The market to supply assets to.
    /// @param assets The amount of assets to supply.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address that will receive the position.
    /// @param data Arbitrary data to pass to the `onMorphoSupply` callback. Pass empty data if not needed.
    /// @return assetsSupplied The amount of assets supplied.
    /// @return sharesSupplied The amount of shares minted.
    function supply(Config memory config, uint256 assets, uint256 shares, address onBehalf, bytes memory data)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied);

    /// @notice Withdraws the given `assets` or `shares` from the given `market` on behalf of `onBehalf` to `receiver`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      To withdraw the whole position, pass the `shares`'s balance of `onBehalf`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Withdrawing an amount corresponding to more shares than supplied will underflow and revert without any error message.
    /// @param config The market to withdraw assets from.
    /// @param assets The amount of assets to withdraw.
    /// @param shares The amount of shares to burn.
    /// @param onBehalf The address of the owner of the withdrawn assets.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @return assetsWithdrawn The amount of assets withdrawn.
    /// @return sharesWithdrawn The amount of shares burned.
    function withdraw(Config memory config, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    /// @notice Borrows the given `assets` or `shares` from the given `market` on behalf of `onBehalf` to `receiver`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      Most usecases should rely on `assets` as an input so the caller
    ///      is guaranteed to borrow `assets` of tokens,
    ///      but the possibility to mint a specific amount of shares is given
    ///      for full compatibility and precision.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Borrowing a large amount can overflow and revert without any error message.
    /// @param config The market to borrow assets from.
    /// @param assets The amount of assets to borrow.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address of the owner of the debt.
    /// @param receiver The address that will receive the debt.
    /// @return assetsBorrowed The amount of assets borrowed.
    /// @return sharesBorrowed The amount of shares minted.
    function borrow(Config memory config, uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    /// @notice Repays the given `assets` or `shares` to the given `market` on behalf of `onBehalf`,
    ///         optionally calling back the caller's `onMorphoReplay` function with the given `data`.
    /// @dev Either `assets` or `shares` should be zero.
    ///      To repay the whole debt, pass the `shares`'s balance of `onBehalf`.
    /// @dev Repaying an amount corresponding to more shares than borrowed will underflow and revert without any error message.
    /// @param config The market to repay assets to.
    /// @param assets The amount of assets to repay.
    /// @param shares The amount of shares to burn.
    /// @param onBehalf The address of the owner of the debt.
    /// @param data Arbitrary data to pass to the `onMorphoRepay` callback. Pass empty data if not needed.
    /// @return assetsRepaid The amount of assets repaid.
    /// @return sharesRepaid The amount of shares burned.
    function repay(Config memory config, uint256 assets, uint256 shares, address onBehalf, bytes memory data)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Supplies the given `assets` of collateral to the given `market` on behalf of `onBehalf`,
    ///         optionally calling back the caller's `onMorphoSupplyCollateral` function with the given `data`.
    /// @dev Interest are not accrued since it's not required and it saves gas.
    /// @dev Supplying a large amount can overflow and revert without any error message.
    /// @param config The market to supply collateral to.
    /// @param assets The amount of collateral to supply.
    /// @param onBehalf The address that will receive the collateral.
    /// @param data Arbitrary data to pass to the `onMorphoSupplyCollateral` callback. Pass empty data if not needed.
    function supplyCollateral(Config memory config, uint256 assets, address onBehalf, bytes memory data) external;

    /// @notice Withdraws the given `assets` of collateral from the given `market` on behalf of `onBehalf` to `receiver`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Withdrawing an amount corresponding to more collateral than supplied will underflow and revert without any error message.
    /// @param config The market to withdraw collateral from.
    /// @param assets The amount of collateral to withdraw.
    /// @param onBehalf The address of the owner of the collateral.
    /// @param receiver The address that will receive the withdrawn collateral.
    function withdrawCollateral(Config memory config, uint256 assets, address onBehalf, address receiver) external;

    /// @notice Liquidates the given `seized` assets to the given `market` of the given `borrower`'s position,
    ///         optionally calling back the caller's `onMorphoLiquidate` function with the given `data`.
    /// @dev Seizing more than the collateral balance will underflow and revert without any error message.
    /// @dev Repaying more than the borrow balance will underflow and revert without any error message.
    /// @param config The market of the position.
    /// @param borrower The owner of the position.
    /// @param seized The amount of collateral to seize.
    /// @param data Arbitrary data to pass to the `onMorphoLiquidate` callback. Pass empty data if not needed.
    /// @return assetsRepaid The amount of assets repaid.
    /// @return sharesRepaid The amount of shares burned.
    function liquidate(Config memory config, address borrower, uint256 seized, bytes memory data)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Executes a flash loan.
    /// @param token The token to flash loan.
    /// @param assets The amount of assets to flash loan.
    /// @param data Arbitrary data to pass to the `onMorphoFlashLoan` callback.
    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    /// @notice Sets the authorization for `authorized` to manage `msg.sender`'s positions.
    /// @param authorized The authorized address.
    /// @param newIsAuthorized The new authorization status.
    function setAuthorization(address authorized, bool newIsAuthorized) external;

    /// @notice Sets the authorization for `authorization.authorized` to manage `authorization.authorizer`'s positions.
    /// @param authorization The `Authorization` struct.
    /// @param signature The signature.
    function setAuthorizationWithSig(Authorization calldata authorization, Signature calldata signature) external;

    /// @notice Accrues interest for `market`.
    function accrueInterest(Config memory config) external;

    /// @notice Returns the data stored on the different `slots`.
    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory res);
}
