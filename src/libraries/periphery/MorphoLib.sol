// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../../interfaces/IMorpho.sol";
import {IIrm} from "../../interfaces/IIrm.sol";

import {MathLib} from "../MathLib.sol";
import {MarketLib} from "../MarketLib.sol";
import {SharesMathLib} from "../SharesMathLib.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

/// @title MorphoLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Helper library exposing getters with the expected value after interests accrual.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
/// @dev The getter to retrieve the total borrow shares is not exposed because interests accrual does not apply to it.
///      The value can be queried directly on Morpho using `totalBorrowShares`.
library MorphoLib {
    using MathLib for uint256;
    using MarketLib for Market;
    using SharesMathLib for uint256;

    function accruedInterests(IMorpho morpho, Market memory market)
        internal
        view
        returns (uint256 totalSupply, uint256 toralBorrow, uint256 totalSupplyShares)
    {
        Id id = market.id();

        bytes32[] memory slots = new bytes32[](5);
        slots[0] = MorphoStorageLib.totalSupplySlot(id);
        slots[1] = MorphoStorageLib.totalBorrowSlot(id);
        slots[2] = MorphoStorageLib.totalSupplySharesSlot(id);
        slots[3] = MorphoStorageLib.feeSlot(id);
        slots[4] = MorphoStorageLib.lastUpdateSlot(id);

        bytes32[] memory values = morpho.extsload(slots);
        totalSupply = uint256(values[0]);
        toralBorrow = uint256(values[1]);
        totalSupplyShares = uint256(values[2]);
        uint256 fee = uint256(values[3]);
        uint256 lastUpdate = uint256(values[4]);

        uint256 elapsed = block.timestamp - lastUpdate;

        if (elapsed == 0) return (totalSupply, toralBorrow, totalSupplyShares);

        if (toralBorrow != 0) {
            uint256 borrowRate = IIrm(market.irm).borrowRateView(market);
            uint256 interests = toralBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            toralBorrow += interests;
            totalSupply += interests;

            if (fee != 0) {
                uint256 feeAmount = interests.wMulDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.toSharesDown(totalSupply - feeAmount, totalSupplyShares);

                totalSupplyShares += feeShares;
            }
        }
    }

    function expectedTotalSupply(IMorpho morpho, Market memory market) internal view returns (uint256 totalSupply) {
        (totalSupply,,) = accruedInterests(morpho, market);
    }

    function expectedTotalBorrow(IMorpho morpho, Market memory market) internal view returns (uint256 totalBorrow) {
        (, totalBorrow,) = accruedInterests(morpho, market);
    }

    function expectedTotalSupplyShares(IMorpho morpho, Market memory market)
        internal
        view
        returns (uint256 totalSupplyShares)
    {
        (,, totalSupplyShares) = accruedInterests(morpho, market);
    }

    function expectedSupplyBalance(IMorpho morpho, Market memory market, address user)
        internal
        view
        returns (uint256)
    {
        Id id = market.id();
        uint256 userSupplyShares = morpho.supplyShares(id, user);
        (uint256 marketTotalSupply,, uint256 marketTotalSupplyShares) = accruedInterests(morpho, market);

        return userSupplyShares.toAssetsDown(marketTotalSupply, marketTotalSupplyShares);
    }

    function expectedBorrowBalance(IMorpho morpho, Market memory market, address user)
        internal
        view
        returns (uint256)
    {
        Id id = market.id();
        uint256 userBorrowShares = morpho.borrowShares(id, user);
        uint256 marketTotalBorrowShares = morpho.totalBorrowShares(id);
        (, uint256 marketTotalBorrow,) = accruedInterests(morpho, market);

        return userBorrowShares.toAssetsUp(marketTotalBorrow, marketTotalBorrowShares);
    }
}
