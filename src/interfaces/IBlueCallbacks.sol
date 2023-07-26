// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function blueLiquidateCallback(uint256 amountSeized, uint256 amountToRepay, bytes calldata data) external;
}

interface IBlueRepayCallback {
    function blueRepayCallback(uint256 amountToRepay, bytes calldata data) external;
}

interface IBlueSupplyCallback {
    function blueSupplyCallback(uint256 amountToSupply, bytes calldata data) external;
}

interface IBlueSupplyCollateralCallback {
    function blueSupplyCollateralCallback(uint256 amountToSupply, bytes calldata data) external;
}
