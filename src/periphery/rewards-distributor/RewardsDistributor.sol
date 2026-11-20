// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {CampaignParams, IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";

/// @dev Fee-on-transfer and rebasing tokens are not supported.
/// @dev No-ops are allowed.
contract RewardsDistributor is IRewardsDistributor {
    using SafeTransferLib for IERC20;

    /* STORAGE */

    mapping(bytes32 id => address) public updater;
    mapping(bytes32 id => address) public sentinel;
    mapping(bytes32 id => uint256) public balance;
    mapping(bytes32 id => bytes32) public root;
    /// @dev Zero means no pending root.
    mapping(bytes32 id => mapping(bytes32 root => uint256)) public validAt;
    mapping(bytes32 id => mapping(address account => uint256)) public claimed;

    /* EXTERNAL */

    /// @dev Delegatecalls preserve msg.sender; any failed call reverts the entire batch.
    /// @dev Useful for EOAs to batch admin calls.
    function multicall(bytes[] calldata data) external returns (bytes[] memory) {
        bytes[] memory results = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
            results[i] = result;
        }
        return results;
    }

    /// @dev A nonzero updater marks a created campaign.
    /// @dev Only the original creator can recreate the ID after its updater is zeroed; other state is preserved.
    /// @dev The salt is derived from msg.sender to prevent front-running issues.
    /// @dev Bundles sharing msg.sender must also bind preSalt to their initiator.
    function createCampaign(address token, uint256 timelock, address newUpdater, bytes32 preSalt)
        external
        returns (bytes32)
    {
        CampaignParams memory params = CampaignParams(token, timelock, keccak256(abi.encode(preSalt, msg.sender)));
        bytes32 id = keccak256(abi.encode(params));
        require(updater[id] == address(0), AlreadyCreated());
        updater[id] = newUpdater;
        emit CreateCampaign(id, msg.sender, params, newUpdater);
        return id;
    }

    function fund(CampaignParams calldata params, uint256 amount) external {
        bytes32 id = keccak256(abi.encode(params));
        require(updater[id] != address(0), UnknownCampaign());
        IERC20 token = IERC20(params.token);
        token.safeTransferFrom(msg.sender, address(this), amount);
        balance[id] += amount;
        emit Fund(id, msg.sender, amount);
    }

    /// @dev Resubmitting a pending root restarts its timelock.
    /// @dev Submitting reverts if adding the timelock to the block timestamp overflows.
    /// @dev Several roots may be pending at once and any matured one can be accepted.
    /// @dev Updaters should revoke roots they no longer want.
    function submitRoot(CampaignParams calldata params, bytes32 newRoot) external {
        bytes32 id = keccak256(abi.encode(params));
        require(msg.sender == updater[id], NotUpdater());
        validAt[id][newRoot] = block.timestamp + params.timelock;
        emit SubmitRoot(id, msg.sender, newRoot);
    }

    function acceptRoot(bytes32 id, bytes32 newRoot) external {
        uint256 rootValidAt = validAt[id][newRoot];
        require(rootValidAt != 0, NoPendingRoot());
        require(block.timestamp >= rootValidAt, TimelockNotExpired());
        root[id] = newRoot;
        validAt[id][newRoot] = 0;
        emit AcceptRoot(id, newRoot);
    }

    /// @dev A matured root may be accepted before this transaction.
    function revokePendingRoot(bytes32 id, bytes32 pendingRoot) external {
        require(msg.sender == updater[id] || msg.sender == sentinel[id], NotUpdaterNorSentinel());
        validAt[id][pendingRoot] = 0;
        emit RevokePendingRoot(id, msg.sender, pendingRoot);
    }

    /// @dev Pending roots are unaffected. The updater should revoke any it does not want accepted.
    function pauseCampaign(bytes32 id) external {
        require(msg.sender == updater[id] || msg.sender == sentinel[id], NotUpdaterNorSentinel());
        root[id] = bytes32(0);
        emit PauseCampaign(id, msg.sender);
    }

    /// @dev The updater transfer is not two-step; the recipient may not exercise the role.
    function setUpdater(bytes32 id, address newUpdater) external {
        require(msg.sender == updater[id], NotUpdater());
        updater[id] = newUpdater;
        emit SetUpdater(id, newUpdater);
    }

    function setSentinel(bytes32 id, address newSentinel) external {
        require(msg.sender == updater[id], NotUpdater());
        sentinel[id] = newSentinel;
        emit SetSentinel(id, newSentinel);
    }

    /// @dev Equal cumulative claims still transfer zero and emit; lower values revert.
    /// @return The incremental amount transferred from the campaign.
    function claim(CampaignParams calldata params, address account, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256)
    {
        bytes32 id = keccak256(abi.encode(params));
        require(claimable >= claimed[id][account], ClaimableTooLow());
        uint256 assets = claimable - claimed[id][account];
        require(assets <= balance[id], InsufficientBalance());
        bytes32 computedRoot = keccak256(bytes.concat(keccak256(abi.encode(account, claimable))));
        for (uint256 i; i < proof.length; ++i) {
            bytes32 sibling = proof[i];
            computedRoot = computedRoot < sibling
                ? keccak256(abi.encodePacked(computedRoot, sibling))
                : keccak256(abi.encodePacked(sibling, computedRoot));
        }
        require(computedRoot == root[id], InvalidProofOrExpired());
        claimed[id][account] = claimable;
        balance[id] -= assets;
        IERC20(params.token).safeTransfer(account, assets);
        emit Claim(id, account, assets);
        return assets;
    }
}
