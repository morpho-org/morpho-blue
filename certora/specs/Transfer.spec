methods {
    function doTransfer(address, address, uint256) external envfree;
    function doTransferFrom(address, address, address, uint256) external envfree;
    function getBalance(address, address) external returns (uint256) envfree;
    function getAllowance(address, address, address) external returns (uint256) envfree;
    function getTotalSupply(address) external returns (uint256) envfree;

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
    mathint initialBalance = getBalance(token, currentContract);
    require to != currentContract => initialBalance + getBalance(token, to) <= to_mathint(getTotalSupply(token));

    doTransfer(token, to, amount);
    mathint finalBalance = getBalance(token, currentContract);

    require myBalances[token] == initialBalance;
    summarySafeTransferFrom(token, currentContract, to, amount);
    assert myBalances[token] == finalBalance;
}

// Check the functional correctness of the summary of safeTransferFrom.
rule checkTransferFromSummary(address token, address from, uint256 amount) {
    mathint initialBalance = getBalance(token, currentContract);
    require from != currentContract => initialBalance + getBalance(token, from) <= to_mathint(getTotalSupply(token));

    doTransferFrom(token, from, currentContract, amount);
    mathint finalBalance = getBalance(token, currentContract);

    require myBalances[token] == initialBalance;
    summarySafeTransferFrom(token, from, currentContract, amount);
    assert myBalances[token] == finalBalance;
}

// Check the revert condition of the summary of safeTransfer.
rule transferRevertCondition(address token, address to, uint256 amount) {
    uint256 initialBalance = getBalance(token, currentContract);
    uint256 toInitialBalance = getBalance(token, to);
    require to != currentContract => initialBalance + toInitialBalance <= to_mathint(getTotalSupply(token));
    require currentContract != 0 && to != 0;

    doTransfer@withrevert(token, to, amount);

    assert lastReverted == (initialBalance < amount);
}

// Check the revert condition of the summary of safeTransferFrom.
rule transferFromRevertCondition(address token, address from, address to, uint256 amount) {
    uint256 initialBalance = getBalance(token, from);
    uint256 toInitialBalance = getBalance(token, to);
    uint256 allowance = getAllowance(token, from, currentContract);
    require to != from => initialBalance + toInitialBalance <= to_mathint(getTotalSupply(token));
    require from != 0 && to != 0;

    doTransferFrom@withrevert(token, from, to, amount);

    assert lastReverted == (initialBalance < amount) || allowance < amount;
}
