// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract ERC20Good is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
}
