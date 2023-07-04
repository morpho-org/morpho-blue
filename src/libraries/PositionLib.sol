// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Position, TrancheId, TrancheShares} from "./Types.sol";
import {TrancheIdLib} from "./TrancheIdLib.sol";

library PositionLib {
    using TrancheIdLib for TrancheId;

    function getTrancheShares(Position storage position, TrancheId trancheId)
        internal
        view
        returns (TrancheShares storage)
    {
        return position.shares[trancheId.index()];
    }

    /// @dev Updates the position's tranches mask to indicate whether the position is borrowing from the given tranche.
    /// Does not emit an event because it is only used for gas optimization and it is pointless to track it offchain.
    function setBorrowing(Position storage position, TrancheId trancheId, bool borrowing) internal {
        position.tranchesMask = trancheId.setBorrowing(position.tranchesMask, borrowing);
    }
}
