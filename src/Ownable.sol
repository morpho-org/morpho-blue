// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/// @title Ownable
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @dev Greatly inspired by Solmate and OZ implementations.
abstract contract Ownable {
    /* STORAGE */

    address public owner;

    /* MODIFIERS */

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /* CONSTRUCTOR */

    constructor(address newOwner) {
        owner = newOwner;
    }

    /* PUBLIC */

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
