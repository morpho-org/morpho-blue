// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id, Info, IMorpho} from "../../interfaces/IMorpho.sol";
import {IIrm} from "../../interfaces/IIrm.sol";

import {MathLib} from "../MathLib.sol";
import {MarketLib} from "../MarketLib.sol";
import {SharesMathLib} from "../SharesMathLib.sol";
import {MorphoLib} from "./MorphoGettersLib.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

/// @title MorphoInterestLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Helper library exposing getters with the expected value after interest accrual.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
/// @dev The getter to retrieve the expected total borrow shares is not exposed because interest accrual does not apply to it.
///      The value can be queried directly on Morpho using `totalBorrowShares`.
library MorphoInterestLib {
    using MarketLib for Info;
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;

    function expectedAccrueInterest(IMorpho morpho, Info memory info)
        internal
        view
        returns (uint256 totalSupply, uint256 toralBorrow, uint256 totalSupplyShares)
    {
        Id id = info.id();

        bytes32[] memory slots = new bytes32[](3);
        slots[0] = MorphoStorageLib.marketSlot(id);
        slots[1] = bytes32(uint256(MorphoStorageLib.marketSlot(id)) + 1);
        slots[2] = bytes32(uint256(MorphoStorageLib.marketSlot(id)) + 2);

        bytes32[] memory values = morpho.extsload(slots);
        totalSupply = uint256(values[0] << 128 >> 128);
        totalSupplyShares = uint256(values[0] >> 128);
        toralBorrow = uint256(values[1] << 128 >> 128);
        uint256 lastUpdate = uint256(values[2] << 128 >> 128);
        uint256 fee = uint256(values[2] >> 128);

        uint256 elapsed = block.timestamp - lastUpdate;

        if (elapsed == 0) return (totalSupply, toralBorrow, totalSupplyShares);

        if (toralBorrow != 0) {
            uint256 borrowRate = IIrm(info.irm).borrowRateView(info);
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

    function expectedTotalSupply(IMorpho morpho, Info memory info) internal view returns (uint256 totalSupply) {
        (totalSupply,,) = expectedAccrueInterest(morpho, info);
    }

    function expectedTotalBorrow(IMorpho morpho, Info memory info) internal view returns (uint256 totalBorrow) {
        (, totalBorrow,) = expectedAccrueInterest(morpho, info);
    }

    function expectedTotalSupplyShares(IMorpho morpho, Info memory info)
        internal
        view
        returns (uint256 totalSupplyShares)
    {
        (,, totalSupplyShares) = expectedAccrueInterest(morpho, info);
    }

    /// @dev Warning: It does not work for `feeRecipient` because their supply shares increase is not taken into account.
    function expectedSupplyBalance(IMorpho morpho, Info memory info, address user) internal view returns (uint256) {
        Id id = info.id();
        uint256 supplyShares = morpho.supplyShares(id, user);
        (uint256 totalSupply,, uint256 totalSupplyShares) = expectedAccrueInterest(morpho, info);

        return supplyShares.toAssetsDown(totalSupply, totalSupplyShares);
    }

    function expectedBorrowBalance(IMorpho morpho, Info memory info, address user) internal view returns (uint256) {
        Id id = info.id();
        uint256 borrowShares = morpho.borrowShares(id, user);
        uint256 totalBorrowShares = morpho.totalBorrowShares(id);
        (, uint256 totalBorrow,) = expectedAccrueInterest(morpho, info);

        return borrowShares.toAssetsUp(totalBorrow, totalBorrowShares);
    }
}
