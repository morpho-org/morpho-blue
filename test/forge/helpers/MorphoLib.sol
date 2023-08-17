// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMorpho, Id} from "../../../src/interfaces/IMorpho.sol";

library MorphoLib {
    function totalSupplyAssets(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (res,) = morpho.totalSupply(id);
    }

    function totalSupplyShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (, res) = morpho.totalSupply(id);
    }

    function totalBorrowAssets(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (res,) = morpho.totalBorrow(id);
    }

    function totalBorrowShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (, res) = morpho.totalBorrow(id);
    }
}
