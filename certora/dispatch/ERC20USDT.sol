// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

contract ERC20USDT {
    uint256 public constant MAX_UINT = 2 ** 256 - 1;

    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
    }

    function transfer(address _to, uint256 _amount) public {
        _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public {
        if (allowance[_from][msg.sender] < MAX_UINT) {
            allowance[_from][msg.sender] -= _amount;
        }
        _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public {
        require(!((_amount != 0) && (allowance[msg.sender][_spender] != 0)));

        allowance[msg.sender][_spender] = _amount;
    }

    function mint(address _receiver, uint256 _amount) public onlyOwner {
        balanceOf[_receiver] += _amount;
        totalSupply += _amount;
    }
}
