methods {
    function extSloads(bytes32[]) external returns bytes32[] => NONDET DELETE(true);
    function getTotalSupplyAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function getTotalSupplyShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function getTotalBorrowAssets(MorphoInternalAccess.Id) external returns uint256 envfree;
    function getTotalBorrowShares(MorphoInternalAccess.Id) external returns uint256 envfree;
    function getSupplyShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function getBorrowShares(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function getCollateral(MorphoInternalAccess.Id, address) external returns uint256 envfree;
    function getFee(MorphoInternalAccess.Id) external returns uint256 envfree;
    function getLastUpdate(MorphoInternalAccess.Id) external returns uint256 envfree;
    function getMarketId(MorphoInternalAccess.MarketParams) external returns MorphoInternalAccess.Id envfree;

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
    if (e.block.timestamp != getLastUpdate(id) && getTotalBorrowAssets(id) != 0) {
        uint128 interest;
        uint256 borrow = getTotalBorrowAssets(id);
        uint256 supply = getTotalSupplyAssets(id);
        require interest + borrow < 2^256;
        require interest + supply < 2^256;
        increaseInterest(e, id, interest);
    }

    update(e, id, e.block.timestamp);
}

definition isCreated(MorphoInternalAccess.Id id) returns bool =
    getLastUpdate(id) != 0;

rule supplyMovesTokensAndIncreasesShares(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    MorphoInternalAccess.Id id = getMarketId(marketParams);

    require e.msg.sender != currentContract;
    require getLastUpdate(id) == e.block.timestamp;

    mathint sharesBefore = getSupplyShares(id, onBehalf);
    mathint balanceBefore = myBalances[marketParams.borrowableToken];

    uint256 suppliedAssets;
    uint256 suppliedShares;
    suppliedAssets, suppliedShares = supply(e, marketParams, assets, shares, onBehalf, data);

    mathint sharesAfter = getSupplyShares(id, onBehalf);
    mathint balanceAfter = myBalances[marketParams.borrowableToken];

    assert assets != 0 => suppliedAssets == assets;
    assert assets == 0 => suppliedShares == shares;
    assert sharesAfter == sharesBefore + suppliedShares;
    assert balanceAfter == balanceBefore + suppliedAssets;
}

rule canRepayAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, bytes data) {
    MorphoInternalAccess.Id id = getMarketId(marketParams);

    require data.length == 0;

    require shares == getBorrowShares(id, e.msg.sender);
    require isCreated(id);
    require e.msg.sender != 0;
    require e.msg.value == 0;
    require shares > 0;
    require getLastUpdate(id) <= e.block.timestamp;
    require shares <= getTotalBorrowShares(id);
    require getTotalBorrowAssets(id) < 10^35;

    repay@withrevert(e, marketParams, 0, shares, e.msg.sender, data);

    assert !lastReverted;
}

rule canWithdrawAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 shares, address receiver) {
    MorphoInternalAccess.Id id = getMarketId(marketParams);

    require shares == getSupplyShares(id, e.msg.sender);
    require isCreated(id);
    require e.msg.sender != 0;
    require receiver != 0;
    require e.msg.value == 0;
    require shares > 0;
    require getTotalBorrowAssets(id) == 0;
    require getLastUpdate(id) <= e.block.timestamp;
    require shares <= getTotalSupplyShares(id);

    withdraw@withrevert(e, marketParams, 0, shares, e.msg.sender, receiver);

    assert !lastReverted;
}

rule canWithdrawCollateralAll(env e, MorphoInternalAccess.MarketParams marketParams, uint256 assets, address receiver) {
    MorphoInternalAccess.Id id = getMarketId(marketParams);

    require assets == getCollateral(id, e.msg.sender);
    require isCreated(id);
    require receiver != 0;
    require e.msg.value == 0;
    require assets > 0;
    require getLastUpdate(id) <= e.block.timestamp;
    require getBorrowShares(id, e.msg.sender) == 0;

    withdrawCollateral@withrevert(e, marketParams, assets, e.msg.sender, receiver);

    assert !lastReverted;
}
