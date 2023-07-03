// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Events} from "src/libraries/Events.sol";
import {MarketKey, Market} from "src/libraries/Types.sol";
import {UnauthorizedIrm} from "src/libraries/Errors.sol";
import {MarketKeyLib} from "src/libraries/MarketKeyLib.sol";

import {Ownable2Step} from "@morpho-utils/access/Ownable2Step.sol";

abstract contract MarketBase is Ownable2Step {
    using MarketKeyLib for MarketKey;

    mapping(bytes32 => Market) private _markets;

    /// @dev Maps a contract address to its whitelisted status. Used to whitelist interest rates model.
    /// Naming is kept abstract because it could be used for any other contract-whitelisting feature (addresses uniquely identifying contracts).
    mapping(address => bool) private _isWhitelisted;

    constructor(address initialOwner) Ownable2Step(initialOwner) {}

    /* EXTERNAL */

    function setIsWhitelisted(address target, bool newIsWhitelisted) external onlyOwner {
        _setIsWhitelisted(target, newIsWhitelisted);
    }

    /* PUBLIC */

    function isWhitelisted(address target) public view returns (bool) {
        return _isWhitelisted[target];
    }

    /* INTERNAL */

    /// @dev Returns the storage pointer to the market uniquely identified by the given configuration.
    /// Note: reverts if the given rate model is not whitelisted by the owner (the DAO).
    function _market(MarketKey calldata marketKey) internal view returns (bytes32 marketId, Market storage market) {
        if (!_isWhitelisted[address(marketKey.rateModel)]) revert UnauthorizedIrm();

        marketId = marketKey.toId();

        market = _markets[marketId];
    }

    function _setIsWhitelisted(address target, bool newIsWhitelisted) internal {
        _isWhitelisted[target] = newIsWhitelisted;

        emit Events.IsWhitelistedSet(target, newIsWhitelisted);
    }
}
