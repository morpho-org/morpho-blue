// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function onBlueLiquidate(uint256 amountSeized, uint256 amountToRepay, bytes calldata data) external;
}

interface IBlueRepayCallback {
    function onBlueRepay(uint256 amountToRepay, bytes calldata data) external;
}

interface IBlueSupplyCallback {
    function onBlueSupply(uint256 amountToSupply, bytes calldata data) external;
}

interface IBlueSupplyCollateralCallback {
    function onBlueSupplyCollateral(uint256 amountToSupply, bytes calldata data) external;
}
