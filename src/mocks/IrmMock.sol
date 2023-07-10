// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {WadRayMath} from "morpho-utils/math/WadRayMath.sol";

import "src/Blue.sol";

contract IrmMock is IIrm {
    using WadRayMath for uint256;

    Blue public immutable blue;

    constructor(Blue blueInstance) {
        blue = Blue(blueInstance);
    }

    function borrowRate(Market calldata market) external view returns (uint256) {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        uint256 utilization = blue.totalBorrow(id).wadDivDown(blue.totalSupply(id));

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
