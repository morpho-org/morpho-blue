// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract ERC20Bad is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        _mint(to, amount);
    }
}
