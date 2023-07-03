// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {BlueGetters} from "src/BlueGetters.sol";
import {BlueStorage} from "src/BlueStorage.sol";
import {Types} from "src/libraries/Types.sol";
import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";

contract Blue is BlueGetters {
    using EnumerableSet for EnumerableSet.AddressSet;

    function initializeMarket(
        Types.MarketParams calldata params,
        address feeRecipient,
        uint96 positionId,
        uint256 fee,
        address callBack
    ) external {
        _initializeMarket(params, feeRecipient, msg.sender, positionId, fee, callBack);
    }

    function initializeTranche(Types.MarketParams calldata params, uint256 lltv, uint256 liquidationBonus)
        external
        marketInitialized(params)
    {
        _initializeTranche(params, lltv, liquidationBonus);
    }

    function supplyCollateral(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        uint96 positionId
    ) external trancheInitialized(params, lltv) assertSolvent(params, lltv) returns (uint256 suppliedCollateral) {
        return _supplyCollateral(params, lltv, amount, msg.sender, onBehalf, positionId);
    }

    function withdrawCollateral(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    ) external trancheInitialized(params, lltv) assertSolvent(params, lltv) returns (uint256 withdrawnCollateral) {
        return _withdrawCollateral(params, lltv, amount, msg.sender, receiver, positionId);
    }

    function supply(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        uint96 positionId
    )
        external
        trancheInitialized(params, lltv)
        callBackAfter(params, lltv)
        assertSolvent(params, lltv)
        returns (uint256 supplied)
    {
        return _supply(params, lltv, amount, msg.sender, onBehalf, positionId);
    }

    function withdraw(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    )
        external
        trancheInitialized(params, lltv)
        callBackAfter(params, lltv)
        assertSolvent(params, lltv)
        returns (uint256 withdrawn)
    {
        return _withdraw(params, lltv, amount, msg.sender, receiver, positionId);
    }

    function borrow(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    )
        external
        trancheInitialized(params, lltv)
        callBackAfter(params, lltv)
        assertSolvent(params, lltv)
        returns (uint256 borrowed)
    {
        return _borrow(params, lltv, amount, msg.sender, receiver, positionId);
    }

    function repay(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        uint96 positionId
    )
        external
        trancheInitialized(params, lltv)
        callBackAfter(params, lltv)
        assertSolvent(params, lltv)
        returns (uint256 repaid)
    {
        return _repay(params, lltv, amount, msg.sender, onBehalf, positionId);
    }

    function liquidate(Types.MarketParams calldata params, uint256 lltv, address liquidatee, uint96 positionId)
        external
        trancheInitialized(params, lltv)
        callBackAfter(params, lltv)
        assertSolvent(params, lltv)
        returns (uint256 liquidated)
    {
        return _liquidate(params, lltv, msg.sender, liquidatee, positionId);
    }

    function addWhitelistedSupplier(Types.MarketParams calldata params, address supplier) external {
        Types.Market storage market = _markets[_marketId(params)];

        require(msg.sender == market.deployer);
        market.wlSuppliers.add(supplier);
    }

    function addWhitelistedBorrower(Types.MarketParams calldata params, address borrower) external {
        Types.Market storage market = _markets[_marketId(params)];

        require(msg.sender == market.deployer);
        market.wlBorrowers.add(borrower);
    }
}
