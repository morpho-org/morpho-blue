// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "src/Morpho.sol";

contract MorphoMock is Morpho {
    using MarketParamsLib for MarketParams;

    constructor(address newOwner) Morpho(newOwner) {}

    function isHealthy(MarketParams memory marketParams, address borrower) public view returns (bool) {
        Id id = marketParams.id();
        return _isHealthy(marketParams, id, borrower);
    }
}
