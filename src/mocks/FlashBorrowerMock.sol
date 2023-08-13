// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashLender} from "../interfaces/IFlashLender.sol";
import {IMorphoFlashLoanCallback} from "../interfaces/IMorphoCallbacks.sol";

import {IERC20, SafeTransferLib} from "../libraries/SafeTransferLib.sol";

contract FlashBorrowerMock is IMorphoFlashLoanCallback {
    using SafeTransferLib for IERC20;

    IFlashLender private immutable MORPHO;

    constructor(IFlashLender newMorpho) {
        MORPHO = newMorpho;
    }

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        MORPHO.flashLoan(token, assets, data);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO));
        address token = abi.decode(data, (address));
        IERC20(token).safeApprove(address(MORPHO), assets);
    }
}
