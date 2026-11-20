// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Campaign, IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../../lib/solmate/src/utils/SafeTransferLib.sol";
import {MerkleProofLib} from "../../../lib/solmate/src/utils/MerkleProofLib.sol";

/// @title RewardsDistributor
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Distributes rewards through independently funded, timelocked Merkle campaigns.
/// @dev Fee-on-transfer and rebasing tokens are not supported.
contract RewardsDistributor is IRewardsDistributor {
    using SafeTransferLib for ERC20;

    /* STORAGE */

    /// @notice The number of campaigns created. IDs start at 1.
    uint256 public campaignCount;
    /// @notice The parameters and remaining funded balance of each campaign.
    mapping(uint256 => Campaign) public campaigns;
    /// @notice The earliest acceptance timestamp for each pending campaign root.
    mapping(uint256 id => mapping(bytes32 root => uint256 validAt)) public pendingRoot;
    /// @notice The cumulative amount already claimed by an account in a campaign.
    mapping(uint256 id => mapping(address account => uint256)) public claimed;

    /* EXTERNAL */

    /// @notice Batches calls to this contract, preserving the caller and reverting the whole batch on failure.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
            results[i] = result;
        }
    }

    /// @notice Creates a campaign with a fixed timelock and no active root.
    /// @return id The newly created campaign ID.
    function createCampaign(address token, address updater, uint256 timelock) external returns (uint256 id) {
        if (token == address(0) || updater == address(0)) revert ZeroAddress();
        id = ++campaignCount;
        campaigns[id] = Campaign(token, updater, timelock, 0, bytes32(0), 0);
        emit CampaignCreated(id, msg.sender, token, updater, timelock);
    }

    /// @notice Funds a campaign with the specified amount from the caller.
    function fund(uint256 id, uint256 amount) external {
        if (campaigns[id].token == address(0)) revert UnknownCampaign();
        ERC20 token = ERC20(campaigns[id].token);
        token.safeTransferFrom(msg.sender, address(this), amount);
        campaigns[id].balance += amount;
        emit Funded(id, msg.sender, amount);
    }

    /// @notice Submits a root, restarting its timelock if it is already pending.
    /// @dev Several roots may be pending at once and any matured one can be accepted. Updaters should revoke roots
    /// they no longer want.
    function submitRoot(uint256 id, bytes32 newRoot) external {
        if (msg.sender != campaigns[id].updater) revert NotUpdater();
        pendingRoot[id][newRoot] = block.timestamp + campaigns[id].timelock;
        emit PendingRootSet(id, msg.sender, newRoot);
    }

    /// @notice Accepts a matured pending root. Anyone may call this function.
    /// @dev Roots submitted at or before the latest pause cannot be accepted.
    function acceptRoot(uint256 id, bytes32 root) external {
        uint256 validAt = pendingRoot[id][root];
        if (validAt == 0) revert NoPendingRoot();
        if (block.timestamp < validAt) revert TimelockNotExpired();
        Campaign storage campaign = campaigns[id];
        if (validAt - campaign.timelock <= campaign.pausedAt) revert RootRevokedByPause();
        campaign.root = root;
        delete pendingRoot[id][root];
        emit RootSet(id, root);
    }

    /// @notice Revokes a pending root. A matured root may be accepted before this transaction.
    function revokePendingRoot(uint256 id, bytes32 root) external {
        if (msg.sender != campaigns[id].updater) revert NotUpdater();
        if (pendingRoot[id][root] == 0) revert NoPendingRoot();
        delete pendingRoot[id][root];
        emit PendingRootRevoked(id, msg.sender, root);
    }

    /// @notice Stops claims and invalidates every root submitted at or before this timestamp.
    /// @dev Resuming requires a timelocked submission in a later block.
    function pauseCampaign(uint256 id) external {
        if (msg.sender != campaigns[id].updater) revert NotUpdater();
        campaigns[id].root = bytes32(0);
        campaigns[id].pausedAt = block.timestamp;
        emit CampaignPaused(id, msg.sender);
    }

    /// @notice Transfers the campaign's updater role to a nonzero address.
    function setUpdater(uint256 id, address newUpdater) external {
        if (msg.sender != campaigns[id].updater) revert NotUpdater();
        if (newUpdater == address(0)) revert ZeroAddress();
        if (newUpdater == campaigns[id].updater) revert AlreadySet();
        campaigns[id].updater = newUpdater;
        emit UpdaterSet(id, newUpdater);
    }

    /// @notice Claims cumulative rewards on behalf of an account, paying only that account.
    /// @return amount The incremental amount transferred from the campaign.
    function claim(uint256 id, address account, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount)
    {
        Campaign storage campaign = campaigns[id];
        if (campaign.root == bytes32(0)) revert RootNotSet();
        if (!MerkleProofLib.verify(
                proof, campaign.root, keccak256(bytes.concat(keccak256(abi.encode(account, campaign.token, claimable))))
            )) revert InvalidProofOrExpired();
        if (claimable <= claimed[id][account]) revert ClaimableTooLow();
        amount = claimable - claimed[id][account];
        if (amount > campaign.balance) revert InsufficientBalance();
        claimed[id][account] = claimable;
        campaign.balance -= amount;
        ERC20(campaign.token).safeTransfer(account, amount);
        emit Claimed(id, account, amount);
    }
}
