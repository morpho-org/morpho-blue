// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "../interfaces/IIrm.sol";
import {Id, MarketParams, IMorpho} from "../interfaces/IMorpho.sol";

import {MathLib} from "../libraries/MathLib.sol";
import {MorphoLib} from "../libraries/periphery/MorphoLib.sol";
import {MarketParamsLib} from "../libraries/MarketParamsLib.sol";

contract IrmMock is IIrm {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    IMorpho private immutable MORPHO;

    constructor(IMorpho morpho) {
        MORPHO = morpho;
    }

    function borrowRate(MarketParams memory marketParams) external view returns (uint256) {
        return borrowRateView(marketParams);
    }

    function borrowRateView(MarketParams memory marketParams) public view returns (uint256) {
        Id id = marketParams.id();
        uint256 utilization = MORPHO.totalBorrowAssets(id).wDivDown(MORPHO.totalSupplyAssets(id));

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
