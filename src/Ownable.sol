// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @title Ownable
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @dev Greatly inspired by Solmate and OZ implementations.
abstract contract Ownable {
    /* EVENTS */

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    /* STORAGE */

    address public owner;

    /* MODIFIERS */

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "not owner");
        _;
    }

    /* CONSTRUCTOR */

    constructor(address newOwner) {
        owner = newOwner;

        emit OwnershipTransferred(address(0), newOwner);
    }

    /* PUBLIC */

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
