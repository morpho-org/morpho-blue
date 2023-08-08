// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IMorphoLiquidateCallback
/// @notice Interface that liquidators willing to use `liquidate`'s callback must implement.
interface IMorphoLiquidateCallback {
    /// @notice Callback called when a liquidation occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param seized The amount of seized tokens.
    /// @param repaid The amount of repaid tokens.
    /// @param data Arbitrary data passed to the `liquidate` function.
    function onMorphoLiquidate(uint256 seized, uint256 repaid, bytes calldata data) external;
}

/// @title IMorphoRepayCallback
/// @notice Interface that users willing to use `repay`'s callback must implement.
interface IMorphoRepayCallback {
    /// @notice Callback called when a repayment occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of repaid tokens.
    /// @param data Arbitrary data passed to the `repay` function.
    function onMorphoRepay(uint256 amount, bytes calldata data) external;
}

/// @title IMorphoSupplyCallback
/// @notice Interface that users willing to use `supply`'s callback must implement.
interface IMorphoSupplyCallback {
    /// @notice Callback called when a supply occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of supplied tokens.
    /// @param data Arbitrary data passed to the `supply` function.
    function onMorphoSupply(uint256 amount, bytes calldata data) external;
}

/// @title IMorphoSupplyCollateralCallback
/// @notice Interface that users willing to use `supplyCollateral`'s callback must implement.
interface IMorphoSupplyCollateralCallback {
    /// @notice Callback called when a supply occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of supplied tokens.
    /// @param data Arbitrary data passed to the `supplyCollateral` function.
    function onMorphoSupplyCollateral(uint256 amount, bytes calldata data) external;
}

/// @title IMorphoWithdrawCallback
/// @notice Interface that users willing to use `withdraw`'s callback must implement.
interface IMorphoFlashLoanCallback {
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param token The token that was flash loaned.
    /// @param amount The amount that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onMorphoFlashLoan(address token, uint256 amount, bytes calldata data) external;
}
