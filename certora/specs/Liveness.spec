// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE;
    function supplyShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function collateral(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function totalSupplyAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalBorrowAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function fee(MorphoInternalAccess.Id) external returns uint256 envfree;
    function lastUpdate(MorphoInternalAccess.Id) external returns uint256 envfree;
    function nonce(address) external returns uint256 envfree;
    function isAuthorized(address, address) external returns bool envfree;

    function Util.libId(MorphoInternalAccess.MarketParams) external returns MorphoInternalAccess.Id envfree;
    function Util.refId(MorphoInternalAccess.MarketParams) external returns MorphoInternalAccess.Id envfree;

    function _._accrueInterest(MorphoInternalAccess.MarketParams memory marketParams, MorphoInternalAccess.Id id) internal with (env e) => summaryAccrueInterest(e, marketParams, id) expect void;

    function MarketParamsLib.id(MorphoInternalAccess.MarketParams memory marketParams) internal returns MorphoInternalAccess.Id => summaryId(marketParams);
    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, currentContract, to, value);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => summarySafeTransferFrom(token, from, to, value);
}

persistent ghost mapping(address => mathint) balance {
    init_state axiom (forall address token. balance[token] == 0);
}

function summaryId(MorphoInternalAccess.MarketParams marketParams) returns MorphoInternalAccess.Id {
    return Util.refId(marketParams);
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

function min(mathint a, mathint b) returns mathint {
    return a < b ? a : b;
}

// Assume no fee.
// Summarize the accrue interest to avoid having to deal with reverts with absurdly high borrow rates.
function summaryAccrueInterest(env e, MorphoInternalAccess.MarketParams marketParams, MorphoInternalAccess.Id id) {
    // Safe require because timestamps cannot realistically be that large.
    require e.block.timestamp < 2^128;
    if (e.block.timestamp != lastUpdate(id) && totalBorrowAssets(id) != 0) {
        uint128 interest;
        uint256 supply = totalSupplyAssets(id);
        // Safe require because the reference implementation would revert.
        require interest + supply < 2^256;
        increaseInterest(e, id, interest);
    }

    update(e, id, e.block.timestamp);
}

definition isCreated(MorphoInternalAccess.Id id) returns bool =
    lastUpdate(id) != 0;

// Check that tokens and shares are properly accounted following a supply.
rule supplyChangesTokensAndShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Safe require because Morpho cannot call such functions by itself.
    require currentContract != e.msg.sender;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = supplyShares(id, onBehalf);
    mathint balanceBefore = balance[marketParams.loanToken];
    mathint liquidityBefore = totalSupplyAssets(id) - totalBorrowAssets(id);

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e, marketParams, assets, shares, onBehalf, data);

    mathint sharesAfter = supplyShares(id, onBehalf);
    mathint balanceAfter = balance[marketParams.loanToken];
    mathint liquidityAfter = totalSupplyAssets(id) - totalBorrowAssets(id);

    assert assets != 0 => suppliedAssets == assets;
    assert shares != 0 => suppliedShares == shares;
    assert sharesAfter == sharesBefore + suppliedShares;
    assert balanceAfter == balanceBefore + suppliedAssets;
    assert liquidityAfter == liquidityBefore + suppliedAssets;
}

// Check that you can supply non-zero tokens by passing shares.
rule canSupplyByPassingShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address onBehalf, bytes data) {
    uint256 suppliedAssets;
    suppliedAssets, _ = supply(e, marketParams, 0, shares, onBehalf, data);

    satisfy suppliedAssets != 0;
}

// Check that tokens and shares are properly accounted following a withdraw.
rule withdrawChangesTokensAndShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Assume that Morpho is not the receiver.
    require currentContract != receiver;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = supplyShares(id, onBehalf);
    mathint balanceBefore = balance[marketParams.loanToken];
    mathint liquidityBefore = totalSupplyAssets(id) - totalBorrowAssets(id);

    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    withdrawnAssets, withdrawnShares = withdraw(e, marketParams, assets, shares, onBehalf, receiver);

    mathint sharesAfter = supplyShares(id, onBehalf);
    mathint balanceAfter = balance[marketParams.loanToken];
    mathint liquidityAfter = totalSupplyAssets(id) - totalBorrowAssets(id);

    assert assets != 0 => withdrawnAssets == assets;
    assert shares != 0 => withdrawnShares == shares;
    assert sharesAfter == sharesBefore - withdrawnShares;
    assert balanceAfter == balanceBefore - withdrawnAssets;
    assert liquidityAfter == liquidityBefore - withdrawnAssets;
}

// Check that you can withdraw non-zero tokens by passing shares.
rule canWithdrawByPassingShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address onBehalf, address receiver) {
    uint256 withdrawnAssets;
    withdrawnAssets, _ = withdraw(e, marketParams, 0, shares, onBehalf, receiver);

    satisfy withdrawnAssets != 0;
}

// Check that tokens and shares are properly accounted following a borrow.
rule borrowChangesTokensAndShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Assume that Morpho is not the receiver.
    require currentContract != receiver;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = borrowShares(id, onBehalf);
    mathint balanceBefore = balance[marketParams.loanToken];
    mathint liquidityBefore = totalSupplyAssets(id) - totalBorrowAssets(id);

    uint256 borrowedAssets;
    uint256 borrowedShares;
    borrowedAssets, borrowedShares = borrow(e, marketParams, assets, shares, onBehalf, receiver);

    mathint sharesAfter = borrowShares(id, onBehalf);
    mathint balanceAfter = balance[marketParams.loanToken];
    mathint liquidityAfter = totalSupplyAssets(id) - totalBorrowAssets(id);

    assert assets != 0 => borrowedAssets == assets;
    assert shares != 0 => borrowedShares == shares;
    assert sharesAfter == sharesBefore + borrowedShares;
    assert balanceAfter == balanceBefore - borrowedAssets;
    assert liquidityAfter == liquidityBefore - borrowedAssets;
}

// Check that you can borrow non-zero tokens by passing shares.
rule canBorrowByPassingShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address onBehalf, address receiver) {
    uint256 borrowedAssets;
    borrowedAssets, _ = borrow(e, marketParams, 0, shares, onBehalf, receiver);

    satisfy borrowedAssets != 0;
}

// Check that tokens and shares are properly accounted following a repay.
rule repayChangesTokensAndShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Safe require because Morpho cannot call such functions by itself.
    require currentContract != e.msg.sender;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = borrowShares(id, onBehalf);
    mathint balanceBefore = balance[marketParams.loanToken];
    mathint liquidityBefore = totalSupplyAssets(id) - totalBorrowAssets(id);

    mathint borrowAssetsBefore = totalBorrowAssets(id);

    uint256 repaidAssets;
    uint256 repaidShares;
    repaidAssets, repaidShares = repay(e, marketParams, assets, shares, onBehalf, data);

    mathint sharesAfter = borrowShares(id, onBehalf);
    mathint balanceAfter = balance[marketParams.loanToken];
    mathint liquidityAfter = totalSupplyAssets(id) - totalBorrowAssets(id);

    assert assets != 0 => repaidAssets == assets;
    assert shares != 0 => repaidShares == shares;
    assert sharesAfter == sharesBefore - repaidShares;
    assert balanceAfter == balanceBefore + repaidAssets;
    // Taking the min to handle the zeroFloorSub in the code.
    assert liquidityAfter == liquidityBefore + min(repaidAssets, borrowAssetsBefore);
}

// Check that you can repay non-zero tokens by passing shares.
rule canRepayByPassingShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address onBehalf, bytes data) {
    uint256 repaidAssets;
    repaidAssets, _ = repay(e, marketParams, 0, shares, onBehalf, data);

    satisfy repaidAssets != 0;
}

// Check that tokens and balances are properly accounted following a supplyCollateral.
rule supplyCollateralChangesTokensAndBalance(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, address onBehalf, bytes data) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Safe require because Morpho cannot call such functions by itself.
    require currentContract != e.msg.sender;

    mathint collateralBefore = collateral(id, onBehalf);
    mathint balanceBefore = balance[marketParams.collateralToken];

    supplyCollateral(e, marketParams, assets, onBehalf, data);

    mathint collateralAfter = collateral(id, onBehalf);
    mathint balanceAfter = balance[marketParams.collateralToken];

    assert collateralAfter == collateralBefore + assets;
    assert balanceAfter == balanceBefore + assets;
}

// Check that tokens and balances are properly accounted following a withdrawCollateral.
rule withdrawCollateralChangesTokensAndBalance(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, address onBehalf, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Assume that Morpho is not the receiver.
    require currentContract != receiver;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint collateralBefore = collateral(id, onBehalf);
    mathint balanceBefore = balance[marketParams.collateralToken];

    withdrawCollateral(e, marketParams, assets, onBehalf, receiver);

    mathint collateralAfter = collateral(id, onBehalf);
    mathint balanceAfter = balance[marketParams.collateralToken];

    assert collateralAfter == collateralBefore - assets;
    assert balanceAfter == balanceBefore - assets;
}

// Check that tokens are properly accounted following a liquidate.
rule liquidateChangesTokens(env e, MorphoInternalAccess.MarketParams marketParams, address borrower, uint256 seized, uint256 repaidShares, bytes data) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Safe require because Morpho cannot call such functions by itself.
    require currentContract != e.msg.sender;
    // Assumption to simplify the balance specification in the rest of this rule.
    require marketParams.loanToken != marketParams.collateralToken;
    // Assumption to ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint collateralBefore = collateral(id, borrower);
    mathint balanceLoanBefore = balance[marketParams.loanToken];
    mathint balanceCollateralBefore = balance[marketParams.collateralToken];
    mathint liquidityBefore = totalSupplyAssets(id) - totalBorrowAssets(id);

    mathint borrowLoanAssetsBefore = totalBorrowAssets(id);

    uint256 seizedAssets;
    uint256 repaidAssets;
    seizedAssets, repaidAssets = liquidate(e, marketParams, borrower, seized, repaidShares, data);

    mathint collateralAfter = collateral(id, borrower);
    mathint balanceLoanAfter = balance[marketParams.loanToken];
    mathint balanceCollateralAfter = balance[marketParams.collateralToken];
    mathint liquidityAfter = totalSupplyAssets(id) - totalBorrowAssets(id);

    assert seized != 0 => seizedAssets == seized;
    assert collateralBefore > to_mathint(seizedAssets) => collateralAfter == collateralBefore - seizedAssets;
    assert balanceLoanAfter == balanceLoanBefore + repaidAssets;
    assert balanceCollateralAfter == balanceCollateralBefore - seizedAssets;
    // Taking the min to handle the zeroFloorSub in the code.
    assert liquidityAfter == liquidityBefore + min(repaidAssets, borrowLoanAssetsBefore);
}

// Check that you can liquidate non-zero tokens by passing shares.
rule canLiquidateByPassingShares(env e, MorphoInternalAccess.MarketParams marketParams, address borrower, uint256 repaidShares, bytes data) {
    uint256 seizedAssets;
    uint256 repaidAssets;
    seizedAssets, repaidAssets = liquidate(e, marketParams, borrower, 0, repaidShares,  data);

    satisfy seizedAssets != 0 && repaidAssets != 0;
}

// Check that nonce and authorization are properly updated with calling setAuthorizationWithSig.
rule setAuthorizationWithSigChangesNonceAndAuthorizes(env e, MorphoInternalAccess.Authorization authorization, MorphoInternalAccess.Signature signature) {
    mathint nonceBefore = nonce(authorization.authorizer);

    setAuthorizationWithSig(e, authorization, signature);

    mathint nonceAfter = nonce(authorization.authorizer);

    assert nonceAfter == nonceBefore + 1;
    assert isAuthorized(authorization.authorizer, authorization.authorized) == authorization.isAuthorized;
}

// Check that one can always repay the debt in full.
rule canRepayAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, bytes data) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Assume no callback, which still allows to repay all.
    require data.length == 0;

    // Assume a full repay.
    require shares == borrowShares(id, e.msg.sender);
    // Omit sanity checks.
    require isCreated(id);
    require e.msg.sender != 0;
    require e.msg.value == 0;
    require shares > 0;
    // Safe require because of the noTimeTravel rule.
    require lastUpdate(id) <= e.block.timestamp;
    // Safe require because of the sumBorrowSharesCorrect invariant.
    require shares <= totalBorrowShares(id);

    // Accrue interest first to ensure that the accrued interest is reasonable (next require).
    // Safe because of the AccrueInterest.repayAccruesInterest rule
    summaryAccrueInterest(e, marketParams, id);

    // Assume that the invariant about tokens total supply is respected.
    require totalBorrowAssets(id) < 10^35;

    repay@withrevert(e, marketParams, 0, shares, e.msg.sender, data);

    assert !lastReverted;
}

// Check the one can always withdraw all, under the condition that there are no outstanding debt on the market.
rule canWithdrawAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Assume a full withdraw.
    require shares == supplyShares(id, e.msg.sender);
    // Omit sanity checks.
    require isCreated(id);
    require e.msg.sender != 0;
    require receiver != 0;
    require e.msg.value == 0;
    require shares > 0;
    // Assume no outstanding debt on the market.
    require totalBorrowAssets(id) == 0;
    // Safe require because of the noTimeTravel rule.
    require lastUpdate(id) <= e.block.timestamp;
    // Safe require because of the sumSupplySharesCorrect invariant.
    require shares <= totalSupplyShares(id);

    withdraw@withrevert(e, marketParams, 0, shares, e.msg.sender, receiver);

    assert !lastReverted;
}

// Check that a user can always withdraw all, under the condition that this user does not have an outstanding debt.
// Combined with the canRepayAll rule, this ensures that a borrower can always fully exit a market.
rule canWithdrawCollateralAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, address receiver) {
    MorphoInternalAccess.Id id = Util.libId(marketParams);

    // Ensure a full withdrawCollateral.
    require assets == collateral(id, e.msg.sender);
    // Omit sanity checks.
    require isCreated(id);
    require receiver != 0;
    require e.msg.value == 0;
    require assets > 0;
    // Safe require because of the noTimeTravel rule.
    require lastUpdate(id) <= e.block.timestamp;
    // Assume that the user does not have an outstanding debt.
    require borrowShares(id, e.msg.sender) == 0;

    withdrawCollateral@withrevert(e, marketParams, assets, e.msg.sender, receiver);

    assert !lastReverted;
}
