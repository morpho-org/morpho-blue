// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "../interfaces/IIrm.sol";
import {Id, Market, IMorpho} from "../interfaces/IMorpho.sol";

import {MathLib} from "../libraries/MathLib.sol";
import {MarketLib} from "../libraries/MarketLib.sol";
import {MorphoLib} from "../../test/forge/helpers/MorphoLib.sol";

contract IrmMock is IIrm {
    using MathLib for uint256;
    using MarketLib for Market;
    using MorphoLib for IMorpho;

    IMorpho private immutable MORPHO;

    constructor(IMorpho morpho) {
        MORPHO = morpho;
    }

    function borrowRate(Market memory market) external view returns (uint256) {
        Id id = market.id();
        uint256 utilization = MORPHO.totalBorrowAssets(id).wDivDown(MORPHO.totalSupplyAssets(id));

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
