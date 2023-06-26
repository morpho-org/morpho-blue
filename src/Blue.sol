// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {BlueGetters} from "src/BlueGetters.sol";
import {BlueStorage} from "src/BlueStorage.sol";
import {Types} from "src/libraries/Types.sol";

contract Blue is BlueGetters {
    function initializeMarket(Types.MarketParams calldata params, address feeRecipient, uint96 positionId) external {
        _initializeMarket(params, feeRecipient, positionId);
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
    ) external trancheInitialized(params, lltv) returns (uint256 withdrawnCollateral) {
        return _withdrawCollateral(params, lltv, amount, msg.sender, receiver, positionId);
    }

    function supply(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        uint96 positionId
    ) external trancheInitialized(params, lltv) returns (uint256 supplied) {
        return _supply(params, lltv, amount, msg.sender, onBehalf, positionId);
    }

    function withdraw(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    ) external trancheInitialized(params, lltv) returns (uint256 withdrawn) {
        return _withdraw(params, lltv, amount, msg.sender, receiver, positionId);
    }

    function borrow(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address receiver,
        uint96 positionId
    ) external trancheInitialized(params, lltv) returns (uint256 borrowed) {
        return _borrow(params, lltv, amount, msg.sender, receiver, positionId);
    }

    function repay(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        uint96 positionId
    ) external trancheInitialized(params, lltv) returns (uint256 repaid) {
        return _repay(params, lltv, amount, msg.sender, onBehalf, positionId);
    }

    function liquidate(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address liquidatee,
        uint96 positionId
    ) external trancheInitialized(params, lltv) returns (uint256 liquidated) {
        return _liquidate(params, lltv, amount, msg.sender, liquidatee, positionId);
    }
}
