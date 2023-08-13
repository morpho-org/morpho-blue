// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "../interfaces/IIrm.sol";
import {Id, MarketParams, IMorpho} from "../interfaces/IMorpho.sol";

import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {MarketLib} from "../libraries/MarketLib.sol";

contract IrmMock is IIrm {
    using FixedPointMathLib for uint256;
    using MarketLib for MarketParams;

    IMorpho private immutable MORPHO;

    constructor(IMorpho morpho) {
        MORPHO = morpho;
    }

    function borrowRate(MarketParams memory marketParams) external view returns (uint256) {
        Id id = marketParams.id();
        uint256 utilization = MORPHO.totalBorrow(id).wDivDown(MORPHO.totalSupply(id));

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
