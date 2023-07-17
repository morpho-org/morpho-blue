// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IIrm} from "src/interfaces/IIrm.sol";

import {MathLib} from "src/libraries/MathLib.sol";
import {Id, Market, MarketLib} from "src/libraries/MarketLib.sol";

import {Blue} from "src/Blue.sol";

contract IrmMock is IIrm {
    using MathLib for uint256;
    using MarketLib for Market;

    Blue public immutable blue;

    constructor(Blue blueInstance) {
        blue = Blue(blueInstance);
    }

    function borrowRate(Market calldata market) external view returns (uint256) {
        Id id = market.toId();
        uint256 utilization = blue.totalBorrow(id).wDiv(blue.totalSupply(id));

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
