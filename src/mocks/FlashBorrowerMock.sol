// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMorpho} from "../interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "../interfaces/IMorphoCallbacks.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract FlashBorrowerMock is IMorphoFlashLoanCallback {
    IMorpho private immutable MORPHO;

    constructor(IMorpho newMorpho) {
        MORPHO = newMorpho;
    }

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        MORPHO.flashLoan(token, assets, data);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO));
        address token = abi.decode(data, (address));
        ERC20(token).approve(address(MORPHO), assets);
    }
}
