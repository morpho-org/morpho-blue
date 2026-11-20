// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Campaign, IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";

/// @title RewardsDistributor
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Distributes rewards through independently funded, timelocked Merkle campaigns.
/// @dev Fee-on-transfer and rebasing tokens are not supported.
contract RewardsDistributor is IRewardsDistributor {
    using SafeTransferLib for IERC20;

    /* STORAGE */

    /// @inheritdoc IRewardsDistributor
    uint256 public campaignCount;
    /// @inheritdoc IRewardsDistributor
    mapping(uint256 => Campaign) public campaigns;
    /// @inheritdoc IRewardsDistributor
    mapping(uint256 id => mapping(bytes32 root => uint256 validAt)) public pendingRoot;
    /// @inheritdoc IRewardsDistributor
    mapping(uint256 id => mapping(address account => uint256)) public claimed;

    /* EXTERNAL */

    /// @notice Batches calls to this contract, preserving the caller and reverting the whole batch on failure.
    /// @dev Useful for EOAs to batch admin calls.
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
        id = ++campaignCount;
        campaigns[id] = Campaign(token, updater, timelock, 0, bytes32(0), 0);
        emit CreateCampaign(id, msg.sender, token, updater, timelock);
    }

    /// @notice Funds a campaign with the specified amount from the caller.
    function fund(uint256 id, uint256 amount) external {
        require(campaigns[id].token != address(0), UnknownCampaign());
        IERC20 token = IERC20(campaigns[id].token);
        token.safeTransferFrom(msg.sender, address(this), amount);
        campaigns[id].balance += amount;
        emit Fund(id, msg.sender, amount);
    }

    /// @notice Submits a root, restarting its timelock if it is already pending.
    /// @dev Will revert if the timelock value is type(uint256).max or any value that overflows when added to the block
    /// timestamp.
    /// @dev Several roots may be pending at once and any matured one can be accepted. Updaters should revoke roots
    /// they no longer want.
    function submitRoot(uint256 id, bytes32 newRoot) external {
        require(msg.sender == campaigns[id].updater, NotUpdater());
        pendingRoot[id][newRoot] = block.timestamp + campaigns[id].timelock;
        emit SubmitRoot(id, msg.sender, newRoot);
    }

    /// @notice Accepts a matured pending root. Anyone may call this function.
    /// @dev Roots submitted at or before the latest pause cannot be accepted.
    function acceptRoot(uint256 id, bytes32 root) external {
        uint256 validAt = pendingRoot[id][root];
        require(validAt != 0, NoPendingRoot());
        require(block.timestamp >= validAt, TimelockNotExpired());
        Campaign storage campaign = campaigns[id];
        require(validAt - campaign.timelock > campaign.pausedAt, RootRevokedByPause());
        campaign.root = root;
        delete pendingRoot[id][root];
        emit AcceptRoot(id, root);
    }

    /// @notice Revokes a pending root. A matured root may be accepted before this transaction.
    function revokePendingRoot(uint256 id, bytes32 root) external {
        require(msg.sender == campaigns[id].updater, NotUpdater());
        require(pendingRoot[id][root] != 0, NoPendingRoot());
        delete pendingRoot[id][root];
        emit RevokePendingRoot(id, msg.sender, root);
    }

    /// @notice Stops claims and invalidates every root submitted at or before this timestamp.
    /// @dev Resuming requires a timelocked submission in a later block.
    function pauseCampaign(uint256 id) external {
        require(msg.sender == campaigns[id].updater, NotUpdater());
        campaigns[id].root = bytes32(0);
        campaigns[id].pausedAt = block.timestamp;
        emit PauseCampaign(id, msg.sender);
    }

    /// @notice Transfers the campaign's updater role.
    /// @dev Roles are not "two-step", so anyone can give a role to anyone, but it does not mean that they will exercise
    /// it.
    function setUpdater(uint256 id, address newUpdater) external {
        require(msg.sender == campaigns[id].updater, NotUpdater());
        require(newUpdater != campaigns[id].updater, AlreadySet());
        campaigns[id].updater = newUpdater;
        emit SetUpdater(id, newUpdater);
    }

    /// @notice Claims cumulative rewards on behalf of an account, paying only that account.
    /// @return amount The incremental amount transferred from the campaign.
    function claim(uint256 id, address account, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount)
    {
        Campaign storage campaign = campaigns[id];
        require(campaign.root != bytes32(0), RootNotSet());
        bytes32 computedRoot = keccak256(bytes.concat(keccak256(abi.encode(account, campaign.token, claimable))));
        for (uint256 i; i < proof.length; ++i) {
            bytes32 sibling = proof[i];
            computedRoot = computedRoot < sibling
                ? keccak256(abi.encodePacked(computedRoot, sibling))
                : keccak256(abi.encodePacked(sibling, computedRoot));
        }
        require(computedRoot == campaign.root, InvalidProofOrExpired());
        require(claimable > claimed[id][account], ClaimableTooLow());
        amount = claimable - claimed[id][account];
        require(amount <= campaign.balance, InsufficientBalance());
        claimed[id][account] = claimable;
        campaign.balance -= amount;
        IERC20(campaign.token).safeTransfer(account, amount);
        emit Claim(id, account, amount);
    }
}
