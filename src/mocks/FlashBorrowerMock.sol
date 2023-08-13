// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashLender} from "../interfaces/IFlashLender.sol";
import {IMorphoFlashLoanCallback} from "../interfaces/IMorphoCallbacks.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FlashBorrowerMock is IMorphoFlashLoanCallback {
    using SafeTransferLib for ERC20;

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
        ERC20(token).safeApprove(address(MORPHO), assets);
    }
}
