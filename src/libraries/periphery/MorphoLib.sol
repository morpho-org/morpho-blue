// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMorpho, Id} from "../../Morpho.sol";
import {MorphoStorageLib} from "./MorphoStorageLib.sol";

library MorphoLib {
    function supplyShares(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        return uint256(morpho.extSloads(_array(MorphoStorageLib.userSupplySharesSlot(id, user)))[0]);
    }

    function borrowShares(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        return
            uint128(uint256(morpho.extSloads(_array(MorphoStorageLib.userBorrowSharesAndCollateralSlot(id, user)))[0]));
    }

    function collateral(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        return uint256(morpho.extSloads(_array(MorphoStorageLib.userBorrowSharesAndCollateralSlot(id, user)))[0] >> 128);
    }

    function totalSupplyAssets(IMorpho morpho, Id id) internal view returns (uint256 res) {
        return uint128(uint256(morpho.extSloads(_array(MorphoStorageLib.marketTotalSupplyAssetsAndSharesSlot(id)))[0]));
    }

    function totalSupplyShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        return uint256(morpho.extSloads(_array(MorphoStorageLib.marketTotalSupplyAssetsAndSharesSlot(id)))[0] >> 128);
    }

    function totalBorrowAssets(IMorpho morpho, Id id) internal view returns (uint256 res) {
        return uint128(uint256(morpho.extSloads(_array(MorphoStorageLib.marketTotalBorrowAssetsAndSharesSlot(id)))[0]));
    }

    function totalBorrowShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        return uint256(morpho.extSloads(_array(MorphoStorageLib.marketTotalBorrowAssetsAndSharesSlot(id)))[0] >> 128);
    }

    function lastUpdate(IMorpho morpho, Id id) internal view returns (uint256 res) {
        return uint128(uint256(morpho.extSloads(_array(MorphoStorageLib.marketLastUpdateAndFeeSlot(id)))[0]));
    }

    function fee(IMorpho morpho, Id id) internal view returns (uint256 res) {
        return uint256(morpho.extSloads(_array(MorphoStorageLib.marketLastUpdateAndFeeSlot(id)))[0] >> 128);
    }

    function _array(bytes32 x) private pure returns (bytes32[] memory) {
        bytes32[] memory res = new bytes32[](1);
        res[0] = x;
        return res;
    }
}
