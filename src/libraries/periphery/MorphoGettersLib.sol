// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMorpho, Id} from "src/Morpho.sol";

library MorphoLib {
    function supplyShares(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        (res,,) = morpho.user(id, user);
    }

    function borrowShares(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        (, res,) = morpho.user(id, user);
    }

    function collateral(IMorpho morpho, Id id, address user) internal view returns (uint256 res) {
        (,, res) = morpho.user(id, user);
    }
}
