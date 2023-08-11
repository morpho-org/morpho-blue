// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IBlue} from "../interfaces/IBlue.sol";
import {IIrm} from "../interfaces/IIrm.sol";

import {MarketLib} from "./MarketLib.sol";
import {BlueStorageLib} from "./BlueStorageLib.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

library BlueLib {
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    function accruedInterests(IBlue blue, Market memory market)
        internal
        view
        returns (uint256 totalSupply, uint256 totalBorrow, uint256 totalSupplyShares)
    {
        Id id = market.id();

        bytes32[] memory slots = new bytes32[](5);
        slots[0] = BlueStorageLib.totalSupply(id);
        slots[1] = BlueStorageLib.totalBorrow(id);
        slots[2] = BlueStorageLib.totalSupplyShares(id);
        slots[3] = BlueStorageLib.fee(id);
        slots[4] = BlueStorageLib.lastUpdate(id);

        bytes32[] memory values = blue.extsload(slots);
        totalSupply = uint256(values[0]);
        totalBorrow = uint256(values[1]);
        totalSupplyShares = uint256(values[2]);
        uint256 fee = uint256(values[3]);
        uint256 lastUpdate = uint256(values[4]);

        if (totalBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRate(market);
            uint256 interests = totalBorrow.wMulDown(borrowRate * (block.timestamp - lastUpdate));

            totalBorrow += interests;
            totalSupply += interests;

            if (fee != 0) {
                uint256 feeAmount = interests.wMulDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.mulDivDown(totalSupplyShares, totalSupply - feeAmount);

                totalSupplyShares += feeShares;
            }
        }
    }
}
