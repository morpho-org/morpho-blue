// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IBlueCallback {
    enum BlueAction {
        SUPPLY,
        SUPPLY_COLLATERAL,
        REPAY,
        LIQUIDATE,
        FLASHLOAN
    }

    function blueCallback(BlueAction action, uint256 amount, bytes calldata data) external;
}
