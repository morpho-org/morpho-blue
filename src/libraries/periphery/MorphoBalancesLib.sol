// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, MarketParams, IMorpho} from "../../interfaces/IMorpho.sol";
import {IIrm} from "../../interfaces/IIrm.sol";

import {MathLib} from "../MathLib.sol";
import {MorphoLib} from "./MorphoLib.sol";
import {SharesMathLib} from "../SharesMathLib.sol";
import {MarketParamsLib} from "../MarketParamsLib.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

/// @title MorphoBalancesLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Helper library exposing getters with the expected value after interest accrual.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
/// @dev The getter to retrieve the expected total borrow shares is not exposed because interest accrual does not apply
/// to it. The value can be queried directly on Morpho using `totalBorrowShares`.
library MorphoBalancesLib {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;

    function expectedMarketBalances(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (
            uint256 totalSupplyAssets,
            uint256 toralBorrowAssets,
            uint256 totalSupplyShares,
            uint256 totalBorrowShares
        )
    {
        Id id = marketParams.id();

        bytes32[] memory slots = new bytes32[](3);
        slots[0] = MorphoStorageLib.marketTotalSupplyAssetsAndSharesSlot(id);
        slots[1] = MorphoStorageLib.marketTotalBorrowAssetsAndSharesSlot(id);
        slots[2] = MorphoStorageLib.marketLastUpdateAndFeeSlot(id);

        bytes32[] memory values = morpho.extSloads(slots);
        totalSupplyAssets = uint128(uint256(values[0]));
        totalSupplyShares = uint256(values[0] >> 128);
        toralBorrowAssets = uint128(uint256(values[1]));
        totalBorrowShares = uint256(values[1] >> 128);
        uint256 lastUpdate = uint128(uint256(values[2]));
        uint256 fee = uint256(values[2] >> 128);

        uint256 elapsed = block.timestamp - lastUpdate;

        if (elapsed != 0 && toralBorrowAssets != 0) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams);
            uint256 interest = toralBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            toralBorrowAssets += interest;
            totalSupplyAssets += interest;

            if (fee != 0) {
                uint256 feeAmount = interest.wMulDown(fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                // that total supply is already updated.
                uint256 feeShares = feeAmount.toSharesDown(totalSupplyAssets - feeAmount, totalSupplyShares);

                totalSupplyShares += feeShares;
            }
        }
    }

    function expectedTotalSupply(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyAssets)
    {
        (totalSupplyAssets,,,) = expectedMarketBalances(morpho, marketParams);
    }

    function expectedTotalBorrow(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalBorrowAssets)
    {
        (, totalBorrowAssets,,) = expectedMarketBalances(morpho, marketParams);
    }

    function expectedTotalSupplyShares(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyShares)
    {
        (,, totalSupplyShares,) = expectedMarketBalances(morpho, marketParams);
    }

    /// @dev Warning: Wrong for `feeRecipient` because their supply shares increase is not taken into account.
    function expectedSupplyBalance(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        uint256 supplyShares = morpho.supplyShares(id, user);
        (uint256 totalSupplyAssets,, uint256 totalSupplyShares,) = expectedMarketBalances(morpho, marketParams);

        return supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function expectedBorrowBalance(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        uint256 borrowShares = morpho.borrowShares(id, user);
        (, uint256 totalBorrowAssets,, uint256 totalBorrowShares) = expectedMarketBalances(morpho, marketParams);

        return borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
    }
}
