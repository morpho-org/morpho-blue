// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, MarketParams, IMorpho} from "../../interfaces/IMorpho.sol";
import {IIrm} from "../../interfaces/IIrm.sol";

import {MathLib} from "../MathLib.sol";
import {MorphoLib} from "./MorphoLib.sol";
import {MarketLib} from "../MarketLib.sol";
import {SharesMathLib} from "../SharesMathLib.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

/// @title MorphoBalancesLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Helper library exposing getters with the expected value after interest accrual.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
/// @dev The getter to retrieve the expected total borrow shares is not exposed because interest accrual does not apply to it.
///      The value can be queried directly on Morpho using `totalBorrowShares`.
library MorphoBalancesLib {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;
    using MarketLib for MarketParams;

    function expectedMarketBalances(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupply, uint256 toralBorrow, uint256 totalSupplyShares)
    {
        Id id = marketParams.id();

        bytes32[] memory slots = new bytes32[](3);
        slots[0] = MorphoStorageLib.marketSlot(id);
        slots[1] = bytes32(uint256(MorphoStorageLib.marketSlot(id)) + 1);
        slots[2] = bytes32(uint256(MorphoStorageLib.marketSlot(id)) + 2);

        bytes32[] memory values = morpho.extsload(slots);
        totalSupply = uint128(uint256(values[0]));
        totalSupplyShares = uint256(values[0] >> 128);
        toralBorrow = uint128(uint256(values[1]));
        uint256 lastUpdate = uint128(uint256(values[2]));
        uint256 fee = uint256(values[2] >> 128);

        uint256 elapsed = block.timestamp - lastUpdate;

        if (elapsed == 0) return (totalSupply, toralBorrow, totalSupplyShares);

        if (toralBorrow != 0) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams);
            uint256 interest = toralBorrow.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            toralBorrow += interest;
            totalSupply += interest;

            if (fee != 0) {
                uint256 feeAmount = interest.wMulDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact that total supply is already updated.
                uint256 feeShares = feeAmount.toSharesDown(totalSupply - feeAmount, totalSupplyShares);

                totalSupplyShares += feeShares;
            }
        }
    }

    function expectedTotalSupply(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupply)
    {
        (totalSupply,,) = expectedMarketBalances(morpho, marketParams);
    }

    function expectedTotalBorrow(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalBorrow)
    {
        (, totalBorrow,) = expectedMarketBalances(morpho, marketParams);
    }

    function expectedTotalSupplyShares(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyShares)
    {
        (,, totalSupplyShares) = expectedMarketBalances(morpho, marketParams);
    }

    /// @dev Warning: It does not work for `feeRecipient` because their supply shares increase is not taken into account.
    function expectedSupplyBalance(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        uint256 supplyShares = morpho.supplyShares(id, user);
        (uint256 totalSupply,, uint256 totalSupplyShares) = expectedMarketBalances(morpho, marketParams);

        return supplyShares.toAssetsDown(totalSupply, totalSupplyShares);
    }

    function expectedBorrowBalance(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        uint256 borrowShares = morpho.borrowShares(id, user);
        uint256 totalBorrowShares = morpho.totalBorrowShares(id);
        (, uint256 totalBorrow,) = expectedMarketBalances(morpho, marketParams);

        return borrowShares.toAssetsUp(totalBorrow, totalBorrowShares);
    }
}
