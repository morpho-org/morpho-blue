// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFlashLender} from "../interfaces/IFlashLender.sol";
import {IMorphoFlashLoanCallback} from "../interfaces/IMorphoFlashLoanCallback.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract FlashBorrowerMock is IMorphoFlashLoanCallback {
    IFlashLender private immutable MORPHO;

    constructor(IFlashLender newMorpho) {
        MORPHO = newMorpho;
    }

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        MORPHO.flashLoan(token, assets, data);
    }

    function onMorphoFlashLoan(address token, uint256 assets, bytes calldata) external {
        require(msg.sender == address(MORPHO));
        ERC20(token).approve(address(MORPHO), assets);
    }
}
