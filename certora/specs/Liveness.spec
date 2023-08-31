methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function totalSupplyAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalSupplyShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalBorrowAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function totalBorrowShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function supplyShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function borrowShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function collateral(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function fee(MorphoInternalAccess.Id) external returns uint256 envfree;
    function lastUpdate(MorphoInternalAccess.Id) external returns uint256 envfree;
    function marketId(MorphoInternalAccess.MarketParams) external returns MorphoInternalAccess.Id envfree;

    function _._accrueInterest(MorphoInternalAccess.MarketParams memory marketParams, MorphoInternalAccess.Id id) internal with (env e) => summaryAccrueInterest(e, marketParams, id) expect void;

    function SafeTransferLib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, currentContract, to, value);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 value) internal => summarySafeTransferFrom(token, from, to, value);
}

ghost mapping(address => mathint) myBalances {
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

// Assume no fee.
function summaryAccrueInterest(env e, MorphoInternalAccess.MarketParams marketParams, MorphoInternalAccess.Id id) {
    require e.block.timestamp < 2^128;
    if (e.block.timestamp != lastUpdate(id) && totalBorrowAssets(id) != 0) {
        uint128 interest;
        uint256 borrow = totalBorrowAssets(id);
        uint256 supply = totalSupplyAssets(id);
        require interest + borrow < 2^256;
        require interest + supply < 2^256;
        increaseInterest(e, id, interest);
    }

    update(e, id, e.block.timestamp);
}

definition isCreated(MorphoInternalAccess.Id id) returns bool =
    lastUpdate(id) != 0;

// Check that tokens and shares are properly accounted following a supply.
rule supplyMovesTokensAndIncreasesShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoInternalAccess.Id id = marketId(marketParams);

    // Safe require that Morpho is not the sender.
    require e.msg.sender != currentContract;
    // Ensure that no interest is accumulated.
    require lastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = supplyShares(id, onBehalf);
    mathint balanceBefore = myBalances[marketParams.borrowableToken];

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e, marketParams, assets, shares, onBehalf, data);

    mathint sharesAfter = supplyShares(id, onBehalf);
    mathint balanceAfter = myBalances[marketParams.borrowableToken];

    assert assets != 0 => suppliedAssets == assets;
    assert assets == 0 => suppliedShares == shares;
    assert sharesAfter == sharesBefore + suppliedShares;
    assert balanceAfter == balanceBefore + suppliedAssets;
}

// This rule is commented out for the moment because of a bug in CVL where market IDs are not consistent accross a run.
// Check that one can always repay the debt in full.
// rule canRepayAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, bytes data) {
//     MorphoInternalAccess.Id id = marketId(marketParams);

//     require data.length == 0;

//     require shares == borrowShares(id, e.msg.sender);
//     require isCreated(id);
//     require e.msg.sender != 0;
//     require e.msg.value == 0;
//     require shares > 0;
//     require lastUpdate(id) <= e.block.timestamp;
//     require shares <= totalBorrowShares(id);
//     require totalBorrowAssets(id) < 10^35;

//     repay@withrevert(e, marketParams, 0, shares, e.msg.sender, data);

//     assert !lastReverted;
// }

// Check the one can always withdraw all, under the condition that there are no outstanding debt on the market.
rule canWithdrawAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address receiver) {
    MorphoInternalAccess.Id id = marketId(marketParams);

    // Require to ensure a withdraw all.
    require shares == supplyShares(id, e.msg.sender);
    // Omit sanity checks.
    require isCreated(id);
    require e.msg.sender != 0;
    require receiver != 0;
    require e.msg.value == 0;
    require shares > 0;
    // Require no outstanding debt on the market.
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
    MorphoInternalAccess.Id id = marketId(marketParams);

    // Ensure a withdrawCollateral all.
    require assets == collateral(id, e.msg.sender);
    // Omit sanity checks.
    require isCreated(id);
    require receiver != 0;
    require e.msg.value == 0;
    require assets > 0;
    // Safe require because of the noTimeTravel rule.
    require lastUpdate(id) <= e.block.timestamp;
    // Require that the user does not have an outstanding debt.
    require borrowShares(id, e.msg.sender) == 0;

    withdrawCollateral@withrevert(e, marketParams, assets, e.msg.sender, receiver);

    assert !lastReverted;
}
