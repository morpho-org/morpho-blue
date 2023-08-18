// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMorpho, Id, Config} from "src/Morpho.sol";

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

    function totalSupply(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (res,,,,,) = morpho.market(id);
    }

    function totalSupplyShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (, res,,,,) = morpho.market(id);
    }

    function totalBorrow(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,, res,,,) = morpho.market(id);
    }

    function totalBorrowShares(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,,, res,,) = morpho.market(id);
    }

    function lastUpdate(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,,,, res,) = morpho.market(id);
    }

    function fee(IMorpho morpho, Id id) internal view returns (uint256 res) {
        (,,,,, res) = morpho.market(id);
    }
}
