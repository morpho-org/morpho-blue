// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function libSafeTransfer(address, address, uint256) external envfree;
    function libSafeTransferFrom(address, address, address, uint256) external envfree;
    function balanceOf(address, address) external returns (uint256) envfree;
    function allowance(address, address, address) external returns (uint256) envfree;
    function totalSupply(address) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.allowance(address, address) external => DISPATCHER(true);
    function _.totalSupply() external => DISPATCHER(true);
}

persistent ghost mapping(address => mathint) balance {
    init_state axiom (forall address token. balance[token] == 0);
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        // Safe require because the reference implementation would revert.
        balance[token] = require_uint256(balance[token] - amount);
    }
    if (to == currentContract) {
        // Safe require because the reference implementation would revert.
        balance[token] = require_uint256(balance[token] + amount);
    }
}

// Check the functional correctness of the summary of safeTransfer.
rule checkTransferSummary(address token, address to, uint256 amount) {
    mathint initialBalance = balanceOf(token, currentContract);
    // Safe require because the total supply is greater than the sum of the balance of any two accounts.
    require to != currentContract => initialBalance + balanceOf(token, to) <= to_mathint(totalSupply(token));

    libSafeTransfer(token, to, amount);
    mathint finalBalance = balanceOf(token, currentContract);

    require balance[token] == initialBalance;
    summarySafeTransferFrom(token, currentContract, to, amount);
    assert balance[token] == finalBalance;
}

// Check the functional correctness of the summary of safeTransferFrom.
rule checkTransferFromSummary(address token, address from, uint256 amount) {
    mathint initialBalance = balanceOf(token, currentContract);
    // Safe require because the total supply is greater than the sum of the balance of any two accounts.
    require from != currentContract => initialBalance + balanceOf(token, from) <= to_mathint(totalSupply(token));

    libSafeTransferFrom(token, from, currentContract, amount);
    mathint finalBalance = balanceOf(token, currentContract);

    require balance[token] == initialBalance;
    summarySafeTransferFrom(token, from, currentContract, amount);
    assert balance[token] == finalBalance;
}

// Check the revert condition of the summary of safeTransfer.
rule transferRevertCondition(address token, address to, uint256 amount) {
    uint256 initialBalance = balanceOf(token, currentContract);
    uint256 toInitialBalance = balanceOf(token, to);
    // Safe require because the total supply is greater than the sum of the balance of any two accounts.
    require to != currentContract => initialBalance + toInitialBalance <= to_mathint(totalSupply(token));

    libSafeTransfer@withrevert(token, to, amount);

    assert lastReverted <=> initialBalance < amount;
}

// Check the revert condition of the summary of safeTransferFrom.
rule transferFromRevertCondition(address token, address from, address to, uint256 amount) {
    uint256 initialBalance = balanceOf(token, from);
    uint256 toInitialBalance = balanceOf(token, to);
    uint256 allowance = allowance(token, from, currentContract);
    // Safe require because the total supply is greater than the sum of the balance of any two accounts.
    require to != from => initialBalance + toInitialBalance <= to_mathint(totalSupply(token));

    libSafeTransferFrom@withrevert(token, from, to, amount);

    assert lastReverted <=> initialBalance < amount || allowance < amount;
}
