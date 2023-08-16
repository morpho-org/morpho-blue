// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract ERC20USDT {
    uint256 public constant MAX_UINT = 2 ** 256 - 1;

    string public name;
    string public symbol;
    uint256 public decimals;
    address owner;
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

    function transfer(address _to, uint256 _value) public {
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
    }

    function transferFrom(address _from, address _to, uint256 _value) public {
        if (allowed[_from][msg.sender] < MAX_UINT) {
            allowed[_from][msg.sender] -= _value;
        }
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
    }

    function approve(address _spender, uint256 _value) public {
        require(!((_value != 0) && (allowed[msg.sender][_spender] != 0)));

        allowed[msg.sender][_spender] = _value;
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function mint(address _receiver, uint256 amount) public onlyOwner {
        balanceOf[owner] += amount;
    }
}
