// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/libraries/SafeTransferLib.sol";
import "../../src/interfaces/IERC20.sol";

interface IERC20Extended is IERC20 {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract TransferHarness {
    using SafeTransferLib for IERC20;

    function doTransfer(address token, address from, address to, uint256 value) public {
        IERC20(token).safeTransferFrom(from, to, value);
    }

    function getBalance(address token, address user) public view returns (uint256) {
        return IERC20Extended(token).balanceOf(user);
    }

    function getTotalSupply(address token) public view returns (uint256) {
        return IERC20Extended(token).totalSupply();
    }
}
