// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IChainlinkAggregator} from "./IChainlinkAggregator.sol";

interface IChainlinkAggregatorV3 is IChainlinkAggregator {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
