// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

contract ERC20NoRevert {
    string public name;
    string public symbol;
    uint256 public decimals;
    address public owner;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowed;

    constructor(string memory _name, string memory _symbol, uint256 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal returns (bool) {
        if (balanceOf[_from] < _amount) {
            return false;
        }
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        return true;
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        return _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        if (allowed[_from][msg.sender] < _amount) {
            return false;
        }
        allowed[_from][msg.sender] -= _amount;
        return _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public {
        allowed[msg.sender][_spender] = _amount;
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function mint(address _receiver, uint256 _amount) public onlyOwner {
        balanceOf[_receiver] += _amount;
        totalSupply += _amount;
    }
}
