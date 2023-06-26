// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {BlueInternal} from "src/BlueInternal.sol";
import {Types} from "src/libraries/Types.sol";

abstract contract BlueGetters is BlueInternal {
    function feeRecipient(Types.MarketParams calldata params) external view returns (bytes32) {
        return _markets[_marketId(params)].feeRecipient;
    }

    function supplyLiquidity(Types.MarketParams calldata params, uint256 lltv)
        external
        view
        returns (Types.Liquidity memory)
    {
        return _markets[_marketId(params)].tranches[lltv].supply;
    }

    function debtLiquidity(Types.MarketParams calldata params, uint256 lltv)
        external
        view
        returns (Types.Liquidity memory)
    {
        return _markets[_marketId(params)].tranches[lltv].debt;
    }

    function liquidationBonus(Types.MarketParams calldata params, uint256 lltv) external view returns (uint256) {
        return _markets[_marketId(params)].tranches[lltv].liquidationBonus;
    }

    function lastUpdateTimestamp(Types.MarketParams calldata params, uint256 lltv) external view returns (uint256) {
        return _markets[_marketId(params)].tranches[lltv].lastUpdateTimestamp;
    }

    function position(Types.MarketParams calldata params, uint256 lltv, address user, uint96 positionId)
        external
        view
        returns (Types.Position memory)
    {
        return _markets[_marketId(params)].tranches[lltv].positions[_userIdKey(user, positionId)];
    }
}
