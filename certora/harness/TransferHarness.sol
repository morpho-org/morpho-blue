// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/libraries/SafeTransferLib.sol";
import "../../src/interfaces/IERC20.sol";

interface IERC20Extended is IERC20 {
    function balanceOf(address) external returns (uint256);
    function totalSupply() external returns (uint256);
}

contract TransferHarness {
    function doTransfer(address token, address from, address to, uint256 value) public {
        IERC20Extended(token).transferFrom(from, to, value);
    }

    function getBalance(address token, address user) public returns (uint256) {
        return IERC20Extended(token).balanceOf(user);
    }

    function getTotalSupply(address token) public returns (uint256) {
        return IERC20Extended(token).totalSupply();
    }
}
