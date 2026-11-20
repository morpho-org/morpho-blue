// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

/// @dev A campaign's immutable parameters. Its ID is keccak256(abi.encode(params)).
struct CampaignParams {
    address token;
    uint256 timelock;
    address initialUpdater;
    bytes32 salt;
}

struct Campaign {
    address updater;
    uint256 balance;
    bytes32 root;
}

interface IRewardsDistributor {
    error AlreadyCreated();
    error UnknownCampaign();
    error NotUpdater();
    error NoPendingRoot();
    error TimelockNotExpired();
    error InvalidProofOrExpired();
    error ClaimableTooLow();
    error InsufficientBalance();

    event CreateCampaign(bytes32 indexed id, address indexed caller, CampaignParams params);
    event Fund(bytes32 indexed id, address indexed caller, uint256 amount);
    event SubmitRoot(bytes32 indexed id, address indexed caller, bytes32 root);
    event RevokePendingRoot(bytes32 indexed id, address indexed caller, bytes32 root);
    event AcceptRoot(bytes32 indexed id, bytes32 root);
    event PauseCampaign(bytes32 indexed id, address indexed caller);
    event SetUpdater(bytes32 indexed id, address indexed updater);
    event Claim(bytes32 indexed id, address indexed account, uint256 amount);

    function campaigns(bytes32 id) external view returns (address updater, uint256 balance, bytes32 root);
    /// @dev Zero means no pending root.
    function validAt(bytes32 id, bytes32 root) external view returns (uint256);
    function claimed(bytes32 id, address account) external view returns (uint256);
    function createCampaign(CampaignParams calldata params) external returns (bytes32 id);
    function fund(CampaignParams calldata params, uint256 amount) external;
    function submitRoot(CampaignParams calldata params, bytes32 newRoot) external;
    function acceptRoot(bytes32 id, bytes32 root) external;
    function revokePendingRoot(bytes32 id, bytes32 root) external;
    function pauseCampaign(bytes32 id) external;
    function setUpdater(bytes32 id, address newUpdater) external;
    function claim(CampaignParams calldata params, address account, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount);
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
