// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";
import {IRateModel} from "../interfaces/IRateModel.sol";

import {NB_TRANCHES} from "./Constants.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

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
    /// @dev The LTV at which a borrower becomes liquidatable on this market.
    uint256 liquidationLtv;
}

/// @dev Holds the shares of a position in a tranche.
struct MarketShares {
    uint256 supply;
    uint256 borrow;
}

struct Position {
    uint256 collateral;
    MarketShares shares;
}

struct MarketState {
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
}

struct Market {
    /// @dev The state of the market.
    MarketState state; // TODO: could be named accounting?
    /// @dev Maps an address to its positions in each tranche.
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
