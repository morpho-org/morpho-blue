// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "src/interfaces/IIrm.sol";

contract IrmArbitraryMock is IIrm {
    uint256 internal rate;

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    function borrowRateView(MarketParams memory, Market memory) public view returns (uint256) {
        return rate;
    }

    function borrowRate(MarketParams memory marketParams, Market memory market) external view returns (uint256) {
        return borrowRateView(marketParams, market);
    }
}
