// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueSupplyCollateralCallback {
    function blueSupplyCollateralCallback(uint256 amountToSupply, bytes calldata data) external;
}
