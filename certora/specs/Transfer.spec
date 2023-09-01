// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function safeTransfer(address, address, uint256) external envfree;
    function safeTransferFrom(address, address, address, uint256) external envfree;
    function balanceOf(address, address) external returns (uint256) envfree;
    function allowance(address, address, address) external returns (uint256) envfree;
    function totalSupply(address) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.allowance(address, address) external => DISPATCHER(true);
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

// Check the functional correctness of the summary of safeTransfer.
rule checkTransferSummary(address token, address to, uint256 amount) {
    mathint initialBalance = balanceOf(token, currentContract);
    require to != currentContract => initialBalance + balanceOf(token, to) <= to_mathint(totalSupply(token));

    safeTransfer(token, to, amount);
    mathint finalBalance = balanceOf(token, currentContract);

    require myBalances[token] == initialBalance;
    summarySafeTransferFrom(token, currentContract, to, amount);
    assert myBalances[token] == finalBalance;
}

// Check the functional correctness of the summary of safeTransferFrom.
rule checkTransferFromSummary(address token, address from, uint256 amount) {
    mathint initialBalance = balanceOf(token, currentContract);
    require from != currentContract => initialBalance + balanceOf(token, from) <= to_mathint(totalSupply(token));

    safeTransferFrom(token, from, currentContract, amount);
    mathint finalBalance = balanceOf(token, currentContract);

    require myBalances[token] == initialBalance;
    summarySafeTransferFrom(token, from, currentContract, amount);
    assert myBalances[token] == finalBalance;
}

// Check the revert condition of the summary of safeTransfer.
rule transferRevertCondition(address token, address to, uint256 amount) {
    uint256 initialBalance = balanceOf(token, currentContract);
    uint256 toInitialBalance = balanceOf(token, to);
    require to != currentContract => initialBalance + toInitialBalance <= to_mathint(totalSupply(token));
    require currentContract != 0 && to != 0;

    safeTransfer@withrevert(token, to, amount);

    assert lastReverted == (initialBalance < amount);
}

// Check the revert condition of the summary of safeTransferFrom.
rule transferFromRevertCondition(address token, address from, address to, uint256 amount) {
    uint256 initialBalance = balanceOf(token, from);
    uint256 toInitialBalance = balanceOf(token, to);
    uint256 allowance = allowance(token, from, currentContract);
    require to != from => initialBalance + toInitialBalance <= to_mathint(totalSupply(token));
    require from != 0 && to != 0;

    safeTransferFrom@withrevert(token, from, to, amount);

    assert lastReverted == (initialBalance < amount) || allowance < amount;
}
