// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function onBlueLiquidate(address token, uint256 amount, bytes calldata data) external;
}

interface IBlueRepayCallback {
    function onBlueRepay(address token, uint256 amount, bytes calldata data) external;
}

interface IBlueSupplyCallback {
    function onBlueSupply(address token, uint256 amount, bytes calldata data) external;
}

interface IBlueSupplyCollateralCallback {
    function onBlueSupplyCollateral(address token, uint256 amount, bytes calldata data) external;
}

interface IBlueFlashLoanCallback {
    function onBlueFlashLoan(address token, uint256 amount, bytes calldata data) external;
}
