// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {Market, IBlue} from "src/interfaces/IBlue.sol";
import {BlueLib} from "src/libraries/BlueLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract CallbackAdapter {
    using FixedPointMathLib for uint256;
    using BlueLib for IBlue;
    using SafeTransferLib for IERC20;

    enum Action {
        Supply,
        SupplyCollateral,
        Repay,
        Liquidate,
        Flashloan
    }

    // THE USER CAN DEFINE THESE FUNCTIONS TO DEPLOY A CUSTOM ADAPTER
    // Notably, the "Callbacks functions" at the end of Blue.t.sol i(onBlueSupply, onBlueSupplyCollateral, ...) could be defined here instead.
    function onSupply() internal virtual {}
    function onSupplyCollateral() internal virtual {}
    function onRepay() internal virtual {}
    function onLiquidate() internal virtual {}
    function onFlashLoan() internal virtual {}

    IBlue immutable blue;

    constructor(address _blue) {
        blue = IBlue(_blue);
    }

    function onBlueCallback(bytes memory data) external {
        Action action = abi.decode(data, (Action));
        if (action == Action.Supply) {
            (, address sender, Market memory m, uint256 amount, address onBehalf) =
                abi.decode(data, (Action, address, Market, uint256, address));
            blue.supply(m, amount, onBehalf);

            onSupply();

            IERC20(m.borrowableAsset).safeTransferFrom(sender, address(this), amount);
            ERC20(m.borrowableAsset).approve(address(blue), amount);
        } else if (action == Action.SupplyCollateral) {
            (, address sender, Market memory m, uint256 amount, address onBehalf) =
                abi.decode(data, (Action, address, Market, uint256, address));
            blue.supplyCollateral(m, amount, onBehalf);

            onSupplyCollateral();

            IERC20(m.collateralAsset).safeTransferFrom(sender, address(this), amount);
            ERC20(m.collateralAsset).approve(address(blue), amount);
        } else if (action == Action.Repay) {
            (, address sender, Market memory m, uint256 shares, address onBehalf) =
                abi.decode(data, (Action, address, Market, uint256, address));
            uint256 amount = blue.repay(m, shares, onBehalf);

            onRepay();

            IERC20(m.borrowableAsset).safeTransferFrom(sender, address(this), amount);
            ERC20(m.borrowableAsset).approve(address(blue), amount);
        } else if (action == Action.Liquidate) {
            (, address sender, Market memory m, address borrower, uint256 seized) =
                abi.decode(data, (Action, address, Market, address, uint256));
            // Notice how doing all the transfers in protocol is annoying here
            uint256 repaid = blue.liquidate(m, borrower, seized);
            IERC20(m.collateralAsset).safeTransfer(sender, seized);

            onLiquidate();

            IERC20(m.borrowableAsset).safeTransferFrom(sender, address(this), repaid);
            ERC20(m.borrowableAsset).approve(address(blue), repaid);
        } else if (action == Action.Flashloan) {
            (, address sender, address token, uint256 amount) = abi.decode(data, (Action, address, address, uint256));
            blue.flashLoan(token, amount);
            IERC20(token).safeTransfer(sender, amount);

            onFlashLoan();

            IERC20(token).safeTransferFrom(sender, address(this), amount);
            ERC20(token).approve(address(blue), amount);
        }
    }

    function supply(Market memory m, uint256 amount, address onBehalf) external {
        blue.interact(abi.encode(Action.Supply, msg.sender, m, amount, onBehalf));
    }

    function supplyCollateral(Market memory m, uint256 amount, address onBehalf) external {
        blue.interact(abi.encode(Action.SupplyCollateral, msg.sender, m, amount, onBehalf));
    }

    function repay(Market memory m, uint256 amount, address onBehalf) external {
        blue.interact(abi.encode(Action.Repay, msg.sender, m, amount, onBehalf));
    }

    function liquidate(Market memory m, address borrower, uint256 seized) external {
        blue.interact(abi.encode(Action.Liquidate, msg.sender, m, borrower, seized));
    }

    function flashLoan(address token, uint256 amount) external {
        blue.interact(abi.encode(Action.Flashloan, msg.sender, token, amount));
    }
}
