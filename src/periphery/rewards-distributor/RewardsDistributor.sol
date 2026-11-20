// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Campaign, PendingRoot} from "./interfaces/IRewardsDistributor.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../../lib/solmate/src/utils/SafeTransferLib.sol";
import {MerkleProofLib} from "../../../lib/solmate/src/utils/MerkleProofLib.sol";
import {ReentrancyGuard} from "../../../lib/solmate/src/utils/ReentrancyGuard.sol";

/// @title RewardsDistributor
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Distributes rewards through independently funded, timelocked Merkle campaigns.
/// @dev Tokens must not rebase or debit senders more than the requested transfer amount.
contract RewardsDistributor is ReentrancyGuard {
    using SafeTransferLib for ERC20;

    /* STORAGE */

    /// @notice The number of campaigns created. IDs start at 1.
    uint256 public campaignCount;
    /// @notice The parameters and remaining funded balance of each campaign.
    mapping(uint256 => Campaign) public campaigns;
    /// @notice The pending root of each campaign.
    mapping(uint256 => PendingRoot) public pendingRoot;
    /// @notice The cumulative amount already claimed by an account in a campaign.
    mapping(uint256 id => mapping(address account => uint256)) public claimed;

    /* MODIFIERS */

    modifier knownCampaign(uint256 id) {
        require(campaigns[id].token != address(0), ErrorsLib.UNKNOWN_CAMPAIGN);
        _;
    }

    modifier onlyUpdater(uint256 id) {
        require(msg.sender == campaigns[id].updater, ErrorsLib.NOT_UPDATER_ROLE);
        _;
    }

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
        require(token != address(0) && updater != address(0), ErrorsLib.ZERO_ADDRESS);
        id = ++campaignCount;
        campaigns[id] = Campaign(token, updater, timelock, 0, bytes32(0));
        emit EventsLib.CampaignCreated(id, msg.sender, token, updater, timelock);
    }

    /// @notice Funds a campaign, crediting only tokens actually received from the caller.
    function fund(uint256 id, uint256 amount) external nonReentrant knownCampaign(id) {
        ERC20 token = ERC20(campaigns[id].token);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        campaigns[id].balance += received;
        emit EventsLib.Funded(id, msg.sender, received);
    }

    /// @notice Submits or replaces a pending root, restarting the campaign's timelock.
    function submitRoot(uint256 id, bytes32 newRoot) external knownCampaign(id) onlyUpdater(id) {
        require(pendingRoot[id].validAt == 0 || newRoot != pendingRoot[id].root, ErrorsLib.ALREADY_PENDING);
        pendingRoot[id] = PendingRoot(newRoot, block.timestamp + campaigns[id].timelock);
        emit EventsLib.PendingRootSet(id, msg.sender, newRoot);
    }

    /// @notice Accepts a matured pending root. Anyone may call this function.
    function acceptRoot(uint256 id) external knownCampaign(id) {
        require(pendingRoot[id].validAt != 0, ErrorsLib.NO_PENDING_ROOT);
        require(block.timestamp >= pendingRoot[id].validAt, ErrorsLib.TIMELOCK_NOT_EXPIRED);
        campaigns[id].root = pendingRoot[id].root;
        delete pendingRoot[id];
        emit EventsLib.RootSet(id, campaigns[id].root);
    }

    /// @notice Revokes a pending root. A matured root may be accepted before this transaction.
    function revokePendingRoot(uint256 id) external knownCampaign(id) onlyUpdater(id) {
        require(pendingRoot[id].validAt != 0, ErrorsLib.NO_PENDING_ROOT);
        delete pendingRoot[id];
        emit EventsLib.PendingRootRevoked(id, msg.sender);
    }

    /// @notice Stops claims and deletes any pending root. Resuming requires a new timelocked submission.
    function pauseCampaign(uint256 id) external knownCampaign(id) onlyUpdater(id) {
        campaigns[id].root = bytes32(0);
        delete pendingRoot[id];
        emit EventsLib.CampaignPaused(id, msg.sender);
    }

    /// @notice Transfers the campaign's updater role to a nonzero address.
    function setUpdater(uint256 id, address newUpdater) external knownCampaign(id) onlyUpdater(id) {
        require(newUpdater != address(0), ErrorsLib.ZERO_ADDRESS);
        require(newUpdater != campaigns[id].updater, ErrorsLib.ALREADY_SET);
        campaigns[id].updater = newUpdater;
        emit EventsLib.UpdaterSet(id, newUpdater);
    }

    /// @notice Claims cumulative rewards on behalf of an account, paying only that account.
    /// @return amount The incremental amount transferred from the campaign.
    function claim(uint256 id, address account, uint256 claimable, bytes32[] calldata proof)
        external
        nonReentrant
        knownCampaign(id)
        returns (uint256 amount)
    {
        Campaign storage campaign = campaigns[id];
        require(campaign.root != bytes32(0), ErrorsLib.ROOT_NOT_SET);
        require(
            MerkleProofLib.verify(
                proof, campaign.root, keccak256(bytes.concat(keccak256(abi.encode(account, campaign.token, claimable))))
            ),
            ErrorsLib.INVALID_PROOF_OR_EXPIRED
        );
        require(claimable > claimed[id][account], ErrorsLib.CLAIMABLE_TOO_LOW);
        amount = claimable - claimed[id][account];
        require(amount <= campaign.balance, ErrorsLib.INSUFFICIENT_BALANCE);
        claimed[id][account] = claimable;
        campaign.balance -= amount;
        ERC20(campaign.token).safeTransfer(account, amount);
        emit EventsLib.Claimed(id, account, amount);
    }
}
