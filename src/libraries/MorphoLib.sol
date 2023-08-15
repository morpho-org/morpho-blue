// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../interfaces/IMorpho.sol";
import {IIrm} from "../interfaces/IIrm.sol";

import {MathLib} from "./MathLib.sol";
import {MarketLib} from "./MarketLib.sol";
import {SharesMathLib} from "./SharesMathLib.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

library MorphoLib {
    using MathLib for uint256;
    using MarketLib for Market;
    using SharesMathLib for uint256;

    function accruedInterests(IMorpho morpho, Market memory market)
        internal
        view
        returns (uint256 totSupply, uint256 totBorrow, uint256 totSupplyShares)
    {
        Id id = market.id();

        bytes32[] memory slots = new bytes32[](5);
        slots[0] = MorphoStorageLib.totalSupply(id);
        slots[1] = MorphoStorageLib.totalBorrow(id);
        slots[2] = MorphoStorageLib.totalSupplyShares(id);
        slots[3] = MorphoStorageLib.fee(id);
        slots[4] = MorphoStorageLib.lastUpdate(id);

        bytes32[] memory values = morpho.extsload(slots);
        totSupply = uint256(values[0]);
        totBorrow = uint256(values[1]);
        totSupplyShares = uint256(values[2]);
        uint256 fee = uint256(values[3]);
        uint256 lastUpdate = uint256(values[4]);

        if (totBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRate(market);
            uint256 interests = totBorrow.wMulDown(borrowRate * (block.timestamp - lastUpdate));

            totBorrow += interests;
            totSupply += interests;

            if (fee != 0) {
                uint256 feeAmount = interests.wMulDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.mulDivDown(totSupplyShares, totSupply - feeAmount);

                totSupplyShares += feeShares;
            }
        }
    }

    function totalSupply(IMorpho morpho, Market memory market) internal view returns (uint256) {
        (uint256 totSupply,,) = accruedInterests(morpho, market);
        return totSupply;
    }

    function totalBorrow(IMorpho morpho, Market memory market) internal view returns (uint256) {
        (, uint256 totBorrow,) = accruedInterests(morpho, market);
        return totBorrow;
    }

    function totalSupplyShares(IMorpho morpho, Market memory market) internal view returns (uint256) {
        (,, uint256 totSupplyShares) = accruedInterests(morpho, market);
        return totSupplyShares;
    }

    function supplyBalance(IMorpho morpho, Market memory market, address user) internal view returns (uint256) {
        Id id = market.id();
        uint256 shares = morpho.supplyShares(id, user);
        (uint256 totSupply,, uint256 totSupplyShares) = accruedInterests(morpho, market);

        return shares.toAssetsDown(totSupply, totSupplyShares);
    }

    function borrowBalance(IMorpho morpho, Market memory market, address user) internal view returns (uint256) {
        Id id = market.id();
        uint256 shares = morpho.borrowShares(id, user);
        uint256 totBorrowShares = morpho.totalBorrowShares(id);
        (, uint256 totBorrow,) = accruedInterests(morpho, market);

        return shares.toAssetsUp(totBorrow, totBorrowShares);
    }
}
