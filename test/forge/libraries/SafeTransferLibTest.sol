// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/libraries/ErrorsLib.sol";
import {IERC20, SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

/// @dev Token not returning any boolean on transfer and transferFrom.
contract ERC20WithoutBoolean {
    mapping(address => uint256) public balanceOf;

    function transfer(address to, uint256 amount) public {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) public {
        // Skip allowance check.
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function setBalance(address account, uint256 amount) public {
        balanceOf[account] = amount;
    }
}

/// @dev Token returning false on transfer and transferFrom.
contract ERC20WithBooleanAlwaysFalse {
    mapping(address => uint256) public balanceOf;

    function transfer(address to, uint256 amount) public returns (bool failure) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        failure = false; // To silence warning.
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool failure) {
        // Skip allowance check.
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        failure = false; // To silence warning.
    }

    function setBalance(address account, uint256 amount) public {
        balanceOf[account] = amount;
    }
}

contract SafeTransferLibTest is Test {
    using SafeTransferLib for *;

    ERC20WithoutBoolean public tokenWithoutBoolean;
    ERC20WithBooleanAlwaysFalse public tokenWithBooleanAlwaysFalse;

    function setUp() public {
        tokenWithoutBoolean = new ERC20WithoutBoolean();
        tokenWithBooleanAlwaysFalse = new ERC20WithBooleanAlwaysFalse();
    }

    function testSafeTransfer(address to, uint256 amount) public {
        tokenWithoutBoolean.setBalance(address(this), amount);

        this.safeTransfer(address(tokenWithoutBoolean), to, amount);
    }

    function testSafeTransferFrom(address from, address to, uint256 amount) public {
        tokenWithoutBoolean.setBalance(from, amount);

        this.safeTransferFrom(address(tokenWithoutBoolean), from, to, amount);
    }

    function testSafeTransferWithBoolFalse(address to, uint256 amount) public {
        tokenWithBooleanAlwaysFalse.setBalance(address(this), amount);

        vm.expectRevert(bytes(ErrorsLib.TRANSFER_FAILED));
        this.safeTransfer(address(tokenWithBooleanAlwaysFalse), to, amount);
    }

    function testSafeTransferFromWithBoolFalse(address from, address to, uint256 amount) public {
        tokenWithBooleanAlwaysFalse.setBalance(from, amount);

        vm.expectRevert(bytes(ErrorsLib.TRANSFER_FROM_FAILED));
        this.safeTransferFrom(address(tokenWithBooleanAlwaysFalse), from, to, amount);
    }

    function safeTransfer(address token, address to, uint256 amount) external {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) external {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
