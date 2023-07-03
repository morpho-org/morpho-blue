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
    ) external trancheInitialized(params, lltv) returns (uint256 suppliedCollateral) {
        return _supplyCollateral(params, lltv, amount, msg.sender, onBehalf, positionId);
    }

    function withdrawCollateral(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    ) external trancheInitialized(params, lltv) accrue(params, lltv) returns (uint256 withdrawnCollateral) {
        withdrawnCollateral = _withdrawCollateral(params, lltv, amount, msg.sender, receiver, positionId);
        require(_liquidityCheck(params, lltv, msg.sender, positionId, _oracleData(params)));
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
        accrue(params, lltv)
        accrueCollateral(params, lltv, onBehalf, positionId)
        returns (uint256 supplied)
    {
        supplied = _supply(params, lltv, amount, msg.sender, onBehalf, positionId);
        _callbackSingle(params, lltv, Types.CallbackData(Types.InteractionType.SUPPLY, amount, onBehalf));
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
        accrue(params, lltv)
        accrueCollateral(params, lltv, msg.sender, positionId)
        returns (uint256 withdrawn)
    {
        withdrawn = _withdraw(params, lltv, amount, msg.sender, receiver, positionId);

        _callbackSingle(params, lltv, Types.CallbackData(Types.InteractionType.WITHDRAW, amount, msg.sender));
    }

    function borrow(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    ) external trancheInitialized(params, lltv) accrue(params, lltv) returns (uint256 borrowed) {
        Types.OracleData memory oracleData = _oracleData(params);
        require(!oracleData.borrowPaused);
        borrowed = _borrow(params, lltv, amount, msg.sender, receiver, positionId);

        _callbackSingle(params, lltv, Types.CallbackData(Types.InteractionType.BORROW, amount, receiver));

        require(_liquidityCheck(params, lltv, msg.sender, positionId, oracleData));
    }

    function repay(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        uint96 positionId
    ) external trancheInitialized(params, lltv) accrue(params, lltv) returns (uint256 repaid) {
        repaid = _repay(params, lltv, amount, msg.sender, onBehalf, positionId);

        _callbackSingle(params, lltv, Types.CallbackData(Types.InteractionType.REPAY, amount, onBehalf));
    }

    function liquidate(Types.MarketParams calldata params, uint256 lltv, address liquidatee, uint96 positionId)
        external
        trancheInitialized(params, lltv)
        accrue(params, lltv)
        returns (uint256 liquidated)
    {
        Types.OracleData memory oracleData = _oracleData(params);
        require(!oracleData.liquidationPaused);

        require(!_liquidityCheck(params, lltv, liquidatee, positionId, oracleData));
        liquidated = _liquidate(params, lltv, msg.sender, liquidatee, positionId);

        _callbackSingle(params, lltv, Types.CallbackData(Types.InteractionType.LIQUIDATE, 0, liquidatee));
    }
}
