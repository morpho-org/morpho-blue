// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../interfaces/IMorpho.sol";
import {IIrm} from "../interfaces/IIrm.sol";

import {MathLib} from "./MathLib.sol";
import {MarketLib} from "./MarketLib.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

library MorphoLib {
    using MathLib for uint256;
    using MarketLib for Market;

    function accruedInterests(IMorpho blue, Market memory market)
        internal
        view
        returns (uint256 totalSupply, uint256 totalBorrow, uint256 totalSupplyShares)
    {
        Id id = market.id();

        bytes32[] memory slots = new bytes32[](5);
        slots[0] = MorphoStorageLib.totalSupply(id);
        slots[1] = MorphoStorageLib.totalBorrow(id);
        slots[2] = MorphoStorageLib.totalSupplyShares(id);
        slots[3] = MorphoStorageLib.fee(id);
        slots[4] = MorphoStorageLib.lastUpdate(id);

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
