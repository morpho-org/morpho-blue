// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title EventsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing events.
library EventsLib {
    event CampaignCreated(
        uint256 indexed id, address indexed caller, address indexed token, address updater, uint256 timelock
    );
    event Funded(uint256 indexed id, address indexed caller, uint256 amount);
    event PendingRootSet(uint256 indexed id, address indexed caller, bytes32 root);
    event PendingRootRevoked(uint256 indexed id, address indexed caller);
    event RootSet(uint256 indexed id, bytes32 root);
    event CampaignPaused(uint256 indexed id, address indexed caller);
    event UpdaterSet(uint256 indexed id, address indexed updater);
    event Claimed(uint256 indexed id, address indexed account, uint256 amount);
}
