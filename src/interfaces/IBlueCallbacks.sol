// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title IBlueLiquidateCallback
/// @notice Interface that liquidators willing to use `liquidate`'s callback must implement.
interface IBlueLiquidateCallback {
    /// @notice Callback called when a liquidation occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of repaid tokens.
    /// @param data Arbitrary data passed to the `liquidate` function.
    function onBlueLiquidate(uint256 amount, bytes calldata data) external;
}

/// @title IBlueRepayCallback
/// @notice Interface that users willing to use `repay`'s callback must implement.
interface IBlueRepayCallback {
    /// @notice Callback called when a repayment occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of repaid tokens.
    /// @param data Arbitrary data passed to the `repay` function.
    function onBlueRepay(uint256 amount, bytes calldata data) external;
}

/// @title IBlueSupplyCallback
/// @notice Interface that users willing to use `supply`'s callback must implement.
interface IBlueSupplyCallback {
    /// @notice Callback called when a supply occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of supplied tokens.
    /// @param data Arbitrary data passed to the `supply` function.
    function onBlueSupply(uint256 amount, bytes calldata data) external;
}

/// @title IBlueSupplyCollateralCallback
/// @notice Interface that users willing to use `supplyCollateral`'s callback must implement.
interface IBlueSupplyCollateralCallback {
    /// @notice Callback called when a supply occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount of supplied tokens.
    /// @param data Arbitrary data passed to the `supplyCollateral` function.
    function onBlueSupplyCollateral(uint256 amount, bytes calldata data) external;
}

/// @title IBlueWithdrawCallback
/// @notice Interface that users willing to use `withdraw`'s callback must implement.
interface IBlueFlashLoanCallback {
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param amount The amount that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onBlueFlashLoan(uint256 amount, bytes calldata data) external;
}
