// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {MathLib} from "src/libraries/MathLib.sol";

import "src/Blue.sol";

contract IrmMock is IIrm {
    using MathLib for uint256;

    Blue public immutable blue;

    constructor(Blue blueInstance) {
        blue = Blue(blueInstance);
    }

    function borrowRate(MarketParams calldata marketParams) external view returns (uint256) {
        Id id = Id.wrap(keccak256(abi.encode(marketParams)));
        uint256 utilization = blue.getMarket(id).totalBorrow.wDiv(blue.getMarket(id).totalSupply);

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
