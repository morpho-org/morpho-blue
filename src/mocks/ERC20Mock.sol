// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function setBalance(address owner, uint256 amount) external {
        uint256 balance = balanceOf(owner);
        if (amount == balance) return;

        if (balance > amount) _burn(owner, balance - amount);
        else _mint(owner, amount - balance);
    }
}
