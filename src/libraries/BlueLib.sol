// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IBlue} from "../interfaces/IBlue.sol";
import {IIrm} from "../interfaces/IIrm.sol";

import {MarketLib} from "./MarketLib.sol";
import {SharesMath} from "./SharesMath.sol";
import {BlueStorageSlots} from "./BlueStorageSlots.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

library BlueLib {
    using MarketLib for Market;
    using SharesMath for uint256;
    using FixedPointMathLib for uint256;

    function withdrawAmount(IBlue blue, Market memory market, uint256 amount, address onBehalf, address receiver)
        internal
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toWithdrawShares(blue.totalSupply(id), blue.totalSupplyShares(id));

        uint256 maxShares = blue.supplyShares(id, address(this));
        if (shares > maxShares) shares = maxShares;

        blue.withdraw(market, shares, onBehalf, receiver);
    }

    function repayAmount(IBlue blue, Market memory market, uint256 amount, address onBehalf, bytes memory data)
        internal
        returns (uint256 shares)
    {
        Id id = market.id();
        shares = amount.toRepayShares(blue.totalBorrow(id), blue.totalBorrowShares(id));

        uint256 maxShares = blue.borrowShares(id, address(this));
        if (shares > maxShares) shares = maxShares;

        blue.repay(market, shares, onBehalf, data);
    }

    function accruedInterests(IBlue blue, Market memory market)
        internal
        view
        returns (uint256 totalSupply, uint256 totalBorrow, uint256 totalSupplyShares)
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
        uint256 fee = uint256(values[3]);
        uint256 lastUpdate = uint256(values[4]);

        if (totalBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRate(market);
            uint256 interests = totalBorrow.mulWadDown(borrowRate * (block.timestamp - lastUpdate));

            totalBorrow += interests;
            totalSupply += interests;

            if (fee != 0) {
                uint256 feeAmount = interests.mulWadDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.mulDivDown(totalSupplyShares, totalSupply - feeAmount);

                totalSupplyShares += feeShares;
            }
        }
    }
}
