// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashBlue} from "../interfaces/IBlueCallbacks.sol";
import {IBlue} from "../interfaces/IBlue.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IFlashBlue {
    using SafeTransferLib for ERC20;

    IBlue private immutable BLUE;

    constructor(IBlue newBlue) {
        BLUE = newBlue;
    }

    function flashLoan(address token, uint256 amount) external {
        BLUE.interact(abi.encode(token, amount));
    }

    function onBlueCallback(bytes calldata data) external {
        (address token, uint256 amount) = abi.decode(data, (address, uint256));
        require(msg.sender == address(BLUE));
        ERC20(token).safeApprove(address(BLUE), amount);
    }
}
