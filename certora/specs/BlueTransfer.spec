methods {
    function doTransfer(address, address, address, uint256) external envfree;
    function getBalance(address, address) external returns (uint256) envfree;
    function getTotalSupply(address) external returns (uint256) envfree;

    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.totalSupply() external => DISPATCHER(true);
}

ghost mapping(address => mathint) myBalances
{
    init_state axiom (forall address token. myBalances[token] == 0);
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        myBalances[token] = require_uint256(myBalances[token] - amount);
    }
    if (to == currentContract) {
        myBalances[token] = require_uint256(myBalances[token] + amount);
    }
}

rule checkTransfer(address token, address from, address to, uint256 amount) {
    require from == currentContract || to == currentContract;

    require from != to => getBalance(token, from) + getBalance(token, to) <= to_mathint(getTotalSupply(token));

    mathint initialBalance = getBalance(token, currentContract);
    doTransfer(token, from, to, amount);
    mathint finalBalance = getBalance(token, currentContract);

    require myBalances[token] == initialBalance;
    summarySafeTransferFrom(token, from, to, amount);
    assert myBalances[token] == finalBalance;
}
