// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "../interfaces/IIrm.sol";
import {Id, Market} from "../interfaces/IMorpho.sol";

import {MathLib} from "../libraries/MathLib.sol";
import {MarketLib} from "../libraries/MarketLib.sol";
import {MorphoLib} from "../libraries/periphery/MorphoLib.sol";

interface IMorpho {
    function market(Id id) external view returns (Market memory);
}

contract IrmMock is IIrm {
    using MathLib for uint128;

    IMorpho private immutable MORPHO;

    constructor(address morpho) {
        MORPHO = IMorpho(morpho);
    }

    function borrowRateView(Id id) external view returns (uint256) {
        return borrowRate(id, MORPHO.market(id));
    }

    function borrowRate(Id, Market memory market) public pure returns (uint256) {
        uint256 utilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);

        // Divide by the number of seconds in a year.
        // This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }
}
