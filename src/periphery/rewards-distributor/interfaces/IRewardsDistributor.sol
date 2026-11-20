// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice A campaign's distribution parameters and remaining funded balance.
struct Campaign {
    address token;
    address updater;
    uint256 timelock;
    uint256 balance;
    bytes32 root;
}

/// @notice A submitted root and the earliest timestamp at which it can be accepted.
struct PendingRoot {
    bytes32 root;
    uint256 validAt;
}

/// @title IRewardsDistributor
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Singleton distribution of independently funded, timelocked rewards campaigns.
interface IRewardsDistributor {
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

    function campaignCount() external view returns (uint256);
    function campaigns(uint256 id)
        external
        view
        returns (address token, address updater, uint256 timelock, uint256 balance, bytes32 root);
    function pendingRoot(uint256 id) external view returns (bytes32 root, uint256 validAt);
    function claimed(uint256 id, address account) external view returns (uint256);
    function createCampaign(address token, address updater, uint256 timelock) external returns (uint256 id);
    function fund(uint256 id, uint256 amount) external;
    function submitRoot(uint256 id, bytes32 newRoot) external;
    function acceptRoot(uint256 id) external;
    function revokePendingRoot(uint256 id) external;
    function pauseCampaign(uint256 id) external;
    function setUpdater(uint256 id, address newUpdater) external;
    function claim(uint256 id, address account, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount);
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
