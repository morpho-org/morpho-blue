// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function onBlueLiquidate(uint256 seized, uint256 repaid, bytes calldata data) external;
}

interface IBlueRepayCallback {
    function onBlueRepay(uint256 amount, bytes calldata data) external;
}

interface IBlueSupplyCallback {
    function onBlueSupply(uint256 amount, bytes calldata data) external;
}

interface IBlueSupplyCollateralCallback {
    function onBlueSupplyCollateral(uint256 amount, bytes calldata data) external;
}

interface IBlueFlashBorrower {
    function onBlueFlashLoan(address token, uint256 amount, bytes calldata data) external;
}
