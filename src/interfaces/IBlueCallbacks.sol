// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function onBlueLiquidate(uint256 seized, uint256 repaid, bytes calldata data) external returns (bytes memory);
}

interface IBlueRepayCallback {
    function onBlueRepay(uint256 amount, bytes calldata data) external returns (bytes memory);
}

interface IBlueSupplyCallback {
    function onBlueSupply(uint256 amount, bytes calldata data) external returns (bytes memory);
}

interface IBlueSupplyCollateralCallback {
    function onBlueSupplyCollateral(uint256 amount, bytes calldata data) external returns (bytes memory);
}
