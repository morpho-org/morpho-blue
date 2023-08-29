pragma solidity 0.8.19;

import "./MorphoHarness.sol";

contract MorphoInternalAccess is MorphoHarness {
    constructor(address newOwner) MorphoHarness(newOwner) {}

    uint128 internal interest;

    function nonDetInterest() external view returns (uint128) {
        return interest;
    }

    function update(Id id, uint256 timestamp) external {
        market[id].lastUpdate = uint128(timestamp);
    }

    function increaseInterest(Id id, uint128 interest) external {
        market[id].totalBorrowAssets += interest;
        market[id].totalSupplyAssets += interest;
    }
}
