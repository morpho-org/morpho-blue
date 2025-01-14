// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./MorphoHarness.sol";

contract MorphoInternalAccess is MorphoHarness {
    constructor(address newOwner) MorphoHarness(newOwner) {}

    function update(Id id, uint256 timestamp) external {
        market[id].lastUpdate = uint128(timestamp);
    }

    function increaseInterest(Id id, uint128 interest) external {
        market[id].totalBorrowAssets += interest;
        market[id].totalSupplyAssets += interest;
    }
}
