// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20Standard is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
}
