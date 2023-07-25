// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, MarketLib} from "src/libraries/MarketLib.sol";
import {BlueStorageSlots} from "src/libraries/BlueStorageSlots.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

import {Blue} from "src/Blue.sol";

library BlueLib {
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    function accruedInterests(Blue blue, Market calldata market)
        internal
        view
        returns (
            uint256 interests,
            uint256 totalSupply,
            uint256 totalBorrow,
            uint256 totalSupplyShares,
            uint256 fee,
            uint256 feeShares,
            uint256 lastUpdate
        )
    {
        Id id = market.id();

        bytes32[] memory slots = new bytes32[](5);
        slots[0] = BlueStorageSlots.totalSupply(id);
        slots[1] = BlueStorageSlots.totalBorrow(id);
        slots[2] = BlueStorageSlots.totalSupplyShares(id);
        slots[3] = BlueStorageSlots.fee(id);
        slots[4] = BlueStorageSlots.lastUpdate(id);

        bytes32[] memory values = blue.extsload(slots);
        totalSupply = uint256(values[0]);
        totalBorrow = uint256(values[1]);
        totalSupplyShares = uint256(values[2]);
        fee = uint256(values[3]);
        lastUpdate = uint256(values[4]);

        if (totalBorrow != 0) {
            uint256 borrowRate = market.irm.borrowRate(market);
            interests = totalBorrow.mulWadDown(borrowRate * (block.timestamp - lastUpdate));

            totalBorrow += interests;
            totalSupply += interests;

            if (fee != 0) {
                uint256 feeAmount = interests.mulWadDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                feeShares = feeAmount.mulDivDown(totalSupplyShares, totalSupply - feeAmount);

                totalSupplyShares += feeShares;
            }
        }
    }
}
