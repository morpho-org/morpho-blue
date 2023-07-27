// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

struct CallbackData {
    address receiver;
    bytes data;
}

interface IBlueLiquidateCallback {
    function onBlueLiquidate(address initiator, uint256 seized, uint256 repaid, bytes calldata data)
        external
        returns (bytes memory);
}

interface IBlueRepayCallback {
    function onBlueRepay(address initiator, uint256 amount, bytes calldata data) external returns (bytes memory);
}

interface IBlueSupplyCallback {
    function onBlueSupply(address initiator, uint256 amount, bytes calldata data) external returns (bytes memory);
}

interface IBlueSupplyCollateralCallback {
    function onBlueSupplyCollateral(address initiator, uint256 amount, bytes calldata data)
        external
        returns (bytes memory);
}
