// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {Campaign, CampaignParams, IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";

/// @title RewardsDistributor
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Fee-on-transfer and rebasing tokens are not supported.
/// @dev No-ops are allowed.
contract RewardsDistributor is IRewardsDistributor {
    using SafeTransferLib for IERC20;

    /* STORAGE */

    mapping(bytes32 id => Campaign) public campaigns;
    /// @dev Zero means no pending root.
    mapping(bytes32 id => mapping(bytes32 root => uint256)) public validAt;
    mapping(bytes32 id => mapping(address account => uint256)) public claimed;

    /* EXTERNAL */

    /// @dev Delegatecalls preserve msg.sender; any failed call reverts the entire batch.
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

    /// @dev A nonzero updater marks a created campaign.
    /// @dev Recreation restores only the initial updater; other state is preserved.
    function createCampaign(CampaignParams calldata params) external returns (bytes32 id) {
        id = keccak256(abi.encode(params));
        require(campaigns[id].updater == address(0), AlreadyCreated());
        campaigns[id].updater = params.initialUpdater;
        emit CreateCampaign(id, msg.sender, params);
    }

    function fund(CampaignParams calldata params, uint256 amount) external {
        bytes32 id = keccak256(abi.encode(params));
        require(campaigns[id].updater != address(0), UnknownCampaign());
        IERC20 token = IERC20(params.token);
        token.safeTransferFrom(msg.sender, address(this), amount);
        campaigns[id].balance += amount;
        emit Fund(id, msg.sender, amount);
    }

    /// @dev Resubmitting a pending root restarts its timelock.
    /// @dev Submitting reverts if adding the timelock to the block timestamp overflows.
    /// @dev Several roots may be pending at once and any matured one can be accepted.
    /// @dev Updaters should revoke roots they no longer want.
    function submitRoot(CampaignParams calldata params, bytes32 newRoot) external {
        bytes32 id = keccak256(abi.encode(params));
        require(msg.sender == campaigns[id].updater, NotUpdater());
        validAt[id][newRoot] = block.timestamp + params.timelock;
        emit SubmitRoot(id, msg.sender, newRoot);
    }

    function acceptRoot(bytes32 id, bytes32 root) external {
        uint256 rootValidAt = validAt[id][root];
        require(rootValidAt != 0, NoPendingRoot());
        require(block.timestamp >= rootValidAt, TimelockNotExpired());
        Campaign storage campaign = campaigns[id];
        campaign.root = root;
        validAt[id][root] = 0;
        emit AcceptRoot(id, root);
    }

    /// @dev A matured root may be accepted before this transaction.
    function revokePendingRoot(bytes32 id, bytes32 root) external {
        require(msg.sender == campaigns[id].updater || msg.sender == campaigns[id].sentinel, NotUpdaterNorSentinel());
        validAt[id][root] = 0;
        emit RevokePendingRoot(id, msg.sender, root);
    }

    /// @dev Pending roots are unaffected. The updater should revoke any it does not want accepted.
    function pauseCampaign(bytes32 id) external {
        require(msg.sender == campaigns[id].updater || msg.sender == campaigns[id].sentinel, NotUpdaterNorSentinel());
        campaigns[id].root = bytes32(0);
        emit PauseCampaign(id, msg.sender);
    }

    /// @dev The updater transfer is not two-step; the recipient may not exercise the role.
    function setUpdater(bytes32 id, address newUpdater) external {
        require(msg.sender == campaigns[id].updater, NotUpdater());
        campaigns[id].updater = newUpdater;
        emit SetUpdater(id, newUpdater);
    }

    function setSentinel(bytes32 id, address newSentinel) external {
        require(msg.sender == campaigns[id].updater, NotUpdater());
        campaigns[id].sentinel = newSentinel;
        emit SetSentinel(id, newSentinel);
    }

    /// @dev Equal cumulative claims still transfer zero and emit; lower values revert.
    /// @return amount The incremental amount transferred from the campaign.
    function claim(CampaignParams calldata params, address account, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount)
    {
        bytes32 id = keccak256(abi.encode(params));
        Campaign storage campaign = campaigns[id];
        bytes32 computedRoot = keccak256(bytes.concat(keccak256(abi.encode(account, params.token, claimable))));
        for (uint256 i; i < proof.length; ++i) {
            bytes32 sibling = proof[i];
            computedRoot = computedRoot < sibling
                ? keccak256(abi.encodePacked(computedRoot, sibling))
                : keccak256(abi.encodePacked(sibling, computedRoot));
        }
        require(computedRoot == campaign.root, InvalidProofOrExpired());
        require(claimable >= claimed[id][account], ClaimableTooLow());
        amount = claimable - claimed[id][account];
        require(amount <= campaign.balance, InsufficientBalance());
        claimed[id][account] = claimable;
        campaign.balance -= amount;
        IERC20(params.token).safeTransfer(account, amount);
        emit Claim(id, account, amount);
    }
}
