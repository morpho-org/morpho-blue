// SPDX-License-Identifier: UNLICENSED

import {Market} from "../interfaces/IBlue.sol";

pragma solidity >=0.5.0;

interface IBlueLiquidateCallback {
    function onBlueLiquidate(Market memory market, uint256 seized, uint256 repaid, bytes calldata data) external;
}

interface IBlueRepayCallback {
    function onBlueRepay(Market memory market, uint256 amount, bytes calldata data) external;
}

interface IBlueSupplyCallback {
    function onBlueSupply(Market memory market, uint256 amount, bytes calldata data) external;
}

interface IBlueSupplyCollateralCallback {
    function onBlueSupplyCollateral(Market memory market, uint256 amount, bytes calldata data) external;
}

interface IBlueFlashLoanCallback {
    function onBlueFlashLoan(address token, uint256 amount, bytes calldata data) external;
}
