// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";

import "src/Blue.sol";

contract IrmMock is IIrm {
    using MathLib for uint;

    Blue public immutable blue;

    constructor(Blue blueInstance) {
        blue = Blue(blueInstance);
    }

    function borrowRate(Market calldata market) external view returns (uint) {
        Id id = Id.wrap(keccak256(abi.encode(market)));
        uint utilization = blue.totalBorrow(id).wDiv(blue.totalSupply(id));

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
