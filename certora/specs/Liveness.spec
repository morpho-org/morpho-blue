// SPDX-License-Identifier: GPL-2.0-or-later

// Liveness properties: a user can always exit the market by repaying, withdrawing, or withdrawing collateral.

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;
    function supplyShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function collateral(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function totalSupplyAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function virtualTotalSupplyAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function virtualTotalSupplyShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalBorrowAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function virtualTotalBorrowAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function virtualTotalBorrowShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function fee(MorphoInternalAccess.Id) external returns uint256 envfree;
    function lastUpdate(MorphoInternalAccess.Id) external returns uint256 envfree;
    function nonce(address) external returns uint256 envfree;
    function isAuthorized(address, address) external returns bool envfree;

    function Util.libId(MorphoInternalAccess.MarketParams) external returns MorphoInternalAccess.Id envfree;
    function Util.refId(MorphoInternalAccess.MarketParams) external returns MorphoInternalAccess.Id envfree;
    function Util.libMulDivDown(uint256 x, uint256 y, uint256 d) external returns uint256 envfree;

    function _._accrueInterest(MorphoInternalAccess.MarketParams memory marketParams, MorphoInternalAccess.Id id) internal with (env e) => summaryAccrueInterest(e, marketParams, id) expect void;

    function MarketParamsLib.id(MorphoInternalAccess.MarketParams memory marketParams) internal returns MorphoInternalAccess.Id => summaryId(marketParams);
    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, currentContract, to, value);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => summarySafeTransferFrom(token, from, to, value);
}

persistent ghost mapping(address => uint256) balance {
    init_state axiom (forall address token. balance[token] == 0);
}

function summaryId(MorphoInternalAccess.MarketParams marketParams) returns MorphoInternalAccess.Id {
    return Util.refId(marketParams);
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        balance[token] = assert_uint256(balance[token] - amount);
    }
    if (to == currentContract) {
        balance[token] = require_uint256(balance[token] + amount);
    }
}

function min(mathint a, mathint b) returns mathint {
    return a < b ? a : b;
}

function summaryAccrueInterest(env e, MorphoInternalAccess.MarketParams marketParams, MorphoInternalAccess.Id id) {
    require e.block.timestamp < 2^128;
    if (e.block.timestamp != lastUpdate(id) && totalBorrowAssets(id) != 0) {
        uint128 interest;
        uint256 supply = totalSupplyAssets(id);
        require interest + supply < 2^128;
        uint256 borrow = totalBorrowAssets(id);
        require borrow <= supply;
        increaseInterest(e, id, interest);
    }

    update(e, id, e.block.timestamp);
}

definition isCreated(MorphoInternalAccess.Id id) returns bool =
    lastUpdate(id) != 0;

// Check that one can always repay the debt in full.
rule canRepayAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, bytes data) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    require data.length == 0;

    require shares == borrowShares(id, e.msg.sender);
    require isCreated(id);
    require e.msg.sender != 0;
    require currentContract != e.msg.sender;
    require e.msg.value == 0;
    require shares > 0;
    require lastUpdate(id) <= e.block.timestamp;
    require shares <= totalBorrowShares(id);

    summaryAccrueInterest(e, marketParams, id);

    require totalBorrowAssets(id) < 10^35;

    repay@withrevert(e, marketParams, 0, shares, e.msg.sender, data);

    assert !lastReverted;
}

// Check the one can always withdraw all, under the condition that there are no outstanding debt on the market.
rule canWithdrawAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    require shares == supplyShares(id, e.msg.sender);
    require isCreated(id);
    require e.msg.sender != 0;
    require receiver != 0;
    require e.msg.value == 0;
    require shares > 0;
    require lastUpdate(id) <= e.block.timestamp;
    require shares <= totalSupplyShares(id);
    require balance[marketParams.loanToken] >= to_mathint(totalSupplyAssets(id));

    summaryAccrueInterest(e, marketParams, id);

    uint256 assets = Util.libMulDivDown(shares, virtualTotalSupplyAssets(id), virtualTotalSupplyShares(id));
    require assets <= totalSupplyAssets(id) - totalBorrowAssets(id);

    withdraw@withrevert(e, marketParams, 0, shares, e.msg.sender, receiver);

    assert !lastReverted;
}

// Check that a user can always withdraw all, under the condition that this user does not have an outstanding debt.
// Combined with the canRepayAll rule, this ensures that a borrower can always fully exit a market.
rule canWithdrawCollateralAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    require assets == collateral(id, e.msg.sender);
    require isCreated(id);
    require receiver != 0;
    require e.msg.value == 0;
    require assets > 0;
    require lastUpdate(id) <= e.block.timestamp;
    require borrowShares(id, e.msg.sender) == 0;
    require balance[marketParams.collateralToken] >= to_mathint(assets);

    withdrawCollateral@withrevert(e, marketParams, assets, e.msg.sender, receiver);

    assert !lastReverted;
}
