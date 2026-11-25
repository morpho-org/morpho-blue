// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// forge-lint: disable-next-line(missing-inheritance) Certora test token, not deployed.
contract ERC20USDT {
    address public owner;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        owner = msg.sender;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
    }

    function transfer(address _to, uint256 _amount) public {
        _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public {
        if (allowance[_from][msg.sender] < type(uint256).max) {
            allowance[_from][msg.sender] -= _amount;
        }
        _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public {
        require(!((_amount != 0) && (allowance[msg.sender][_spender] != 0)));

        allowance[msg.sender][_spender] = _amount;
    }

    function mint(address _receiver, uint256 _amount) public {
        require(msg.sender == owner);
        balanceOf[_receiver] += _amount;
        totalSupply += _amount;
    }
}
