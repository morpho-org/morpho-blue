// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {NB_TRANCHES} from "src/libraries/Constants.sol";

/// @dev The id uniquely identifying a tranche. Used for type safety.
type TrancheId is uint256;

/// @dev Holds the configuration defining a market's components.
struct MarketKey {
    /// @dev The asset that can be deposited and borrowed.
    ERC20 asset;
    /// @dev The asset that can be used as collateral by borrowers.
    ERC20 collateral;
    /// @dev The oracle used to quote collateral in assets.
    IOracle oracle;
    /// @dev The contract holding logic responsible for controlling the borrow rate of a tranche.
    /// Supply rate is deducted from the borrow rate and the tranche's utilization.
    IRateModel rateModel;
}

/// @dev Holds the shares of a position in a tranche.
struct TrancheShares {
    uint256 supply;
    uint256 borrow;
}

struct Position {
    /// @dev The amount of collateral deposited.
    uint256 collateral;
    /// @dev A bitmask where bit N represents whether the position borrows from tranche N.
    uint256 tranchesMask;
    /// @dev The shares of the position for each tranche.
    TrancheShares[NB_TRANCHES] shares;
}

struct Tranche {
    /// @dev The total supply. Shared among the tranche's supply shareholders.
    uint256 totalSupply;
    /// @dev The total borrow. Shared among the tranche's borrow shareholders.
    uint256 totalBorrow;
    /// @dev The total number of supply shares held.
    uint256 totalSupplyShares;
    /// @dev The total number of borrow shares held.
    uint256 totalBorrowShares;
    /// @dev The latest timestamp at which the tranche was accrued.
    /// Used to calculate interests accrued since the last interaction with the tranche.
    uint256 lastAccrualTimestamp;
    /// @dev The rate at which borrow interests accrued last time the tranche was accrued.
    /// Used to calculate interests accrued since the last interaction with the tranche.
    uint256 lastBorrowRate;
}

struct Market {
    /// @dev Each tranche of the market.
    Tranche[NB_TRANCHES] tranches;
    /// @dev Maps an address to its position in the given market.
    /// Not stored under `Tranche` to enable Tranche to be manipulated in memory.
    /// Keys could be `bytes32` where the first 12 bytes is a nonce representing a sub-account id and the 20 last bytes are the holder's address.
    /// With appropriate changes:
    /// 1. address onBehalf => bytes32 onBehalf
    /// 2. (msg.sender == onBehalf) => (msg.sender == address(bytes20(onBehalf)))
    /// It would unlock sub-account management without having heavy trade-offs. Idea from @makcandrov.
    mapping(address => Position) positions;
}

struct SignedApproval {
    address delegator;
    address manager;
    uint256 allowance;
    uint256 nonce;
    uint256 deadline;
}
