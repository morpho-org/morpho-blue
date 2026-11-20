// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {Test} from "../../../lib/forge-std/src/Test.sol";
import {Merkle} from "./helpers/Merkle.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {RewardsDistributor} from "../../../src/periphery/rewards-distributor/RewardsDistributor.sol";
import {IRewardsDistributor} from "../../../src/periphery/rewards-distributor/interfaces/IRewardsDistributor.sol";
import {ErrorsLib} from "../../../src/libraries/ErrorsLib.sol";

contract RewardsToken is ERC20Mock {
    function mint(address account, uint256 amount) external {
        setBalance(account, balanceOf[account] + amount);
    }
}

contract RewardsDistributorTest is Test {
    uint256 internal constant TIMELOCK = 6 hours;
    RewardsDistributor internal distributor;
    IRewardsDistributor internal distribution;
    RewardsToken internal token;
    Merkle internal merkle;
    address internal updater = makeAddr("updater");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal id;

    function setUp() public {
        distributor = new RewardsDistributor();
        distribution = IRewardsDistributor(address(distributor));
        token = new RewardsToken();
        merkle = new Merkle();
        id = distributor.createCampaign(address(token), updater, TIMELOCK);
        token.mint(address(this), 1e30);
        token.approve(address(distributor), type(uint256).max);
    }

    function _balance(uint256 campaignId) internal view returns (uint256 balance) {
        (,,, balance,) = distributor.campaigns(campaignId);
    }

    function _root(uint256 campaignId) internal view returns (bytes32 root) {
        (,,,, root) = distributor.campaigns(campaignId);
    }

    function _tree(address reward, uint256 amount) internal view returns (bytes32[] memory leaves) {
        leaves = new bytes32[](2);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, reward, amount))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, reward, amount))));
    }

    function _submit(uint256 campaignId, bytes32 root) internal {
        vm.prank(updater);
        distributor.submitRoot(campaignId, root);
    }

    function _activate(uint256 campaignId, bytes32 root) internal {
        _submit(campaignId, root);
        uint256 validAt = distributor.validAt(campaignId, root);
        vm.warp(validAt);
        distributor.acceptRoot(campaignId, root);
    }

    function testCreateCampaign(address creator, uint256 timelock) public {
        vm.expectEmit(true, true, true, true);
        emit IRewardsDistributor.CreateCampaign(2, creator, address(token), updater, timelock);
        vm.prank(creator);
        uint256 otherId = distributor.createCampaign(address(token), updater, timelock);
        assertEq(otherId, 2);
        assertEq(distribution.campaignCount(), 2);
        (address reward, address actualUpdater, uint256 delay, uint256 balance, bytes32 root) =
            distribution.campaigns(otherId);
        assertEq(reward, address(token));
        assertEq(actualUpdater, updater);
        assertEq(delay, timelock);
        assertEq(balance, 0);
        assertEq(root, bytes32(0));
    }

    function testFund(uint128 amount) public {
        token.mint(bob, amount);
        vm.prank(bob);
        token.approve(address(distributor), amount);
        vm.expectEmit(true, true, false, true);
        emit IRewardsDistributor.Fund(id, bob, amount);
        vm.prank(bob);
        distributor.fund(id, amount);
        assertEq(_balance(id), amount);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(token.balanceOf(bob), 0);
    }

    function testDirectTransferDoesNotCreditCampaign() public {
        token.transfer(address(distributor), 100);
        assertEq(_balance(id), 0);
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        _activate(id, merkle.getRoot(leaves));
        vm.expectRevert(IRewardsDistributor.InsufficientBalance.selector);
        distributor.claim(id, alice, 100, proof);
        distributor.fund(id, 40);
        assertEq(_balance(id), 40);
        assertEq(token.balanceOf(address(distributor)), 140);
    }

    function testCampaignIsolation(uint128 fundingA, uint128 fundingB) public {
        uint256 amountB = bound(fundingB, 1, type(uint128).max);
        uint256 otherId = distributor.createCampaign(address(token), updater, TIMELOCK);
        token.mint(address(this), uint256(fundingA) + amountB);
        distributor.fund(id, fundingA);
        distributor.fund(otherId, amountB);
        bytes32[] memory badLeaves = _tree(address(token), uint256(fundingA) + 1);
        bytes32[] memory goodLeaves = _tree(address(token), amountB);
        bytes32[] memory badProof = merkle.getProof(badLeaves, 0);
        bytes32[] memory goodProof = merkle.getProof(goodLeaves, 0);
        _activate(id, merkle.getRoot(badLeaves));
        _activate(otherId, merkle.getRoot(goodLeaves));
        vm.expectRevert(IRewardsDistributor.InsufficientBalance.selector);
        distributor.claim(id, alice, uint256(fundingA) + 1, badProof);
        assertEq(distributor.claimed(id, alice), 0);
        assertEq(_balance(id), fundingA);
        assertEq(_balance(otherId), amountB);
        distributor.claim(otherId, alice, amountB, goodProof);
        assertEq(token.balanceOf(alice), amountB);
        assertEq(_balance(otherId), 0);
        assertEq(token.balanceOf(address(distributor)), fundingA);
    }

    function testTimelockAndPermissionlessAccept(address caller) public {
        bytes32 root = bytes32(uint256(42));
        _submit(id, root);
        uint256 validAt = distributor.validAt(id, root);
        assertEq(validAt, block.timestamp + TIMELOCK);
        vm.warp(validAt - 1);
        vm.expectRevert(IRewardsDistributor.TimelockNotExpired.selector);
        distributor.acceptRoot(id, root);
        vm.warp(validAt);
        vm.expectEmit(true, false, false, true);
        emit IRewardsDistributor.AcceptRoot(id, root);
        vm.prank(caller);
        distributor.acceptRoot(id, root);
        assertEq(_root(id), root);
        assertEq(distributor.validAt(id, root), 0);
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.acceptRoot(id, root);
    }

    function testIndependentTimelocks() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, 2 * TIMELOCK);
        _submit(id, bytes32(uint256(1)));
        _submit(otherId, bytes32(uint256(2)));
        uint256 validAtA = distributor.validAt(id, bytes32(uint256(1)));
        uint256 validAtB = distributor.validAt(otherId, bytes32(uint256(2)));
        assertEq(validAtB, validAtA + TIMELOCK);
        vm.warp(validAtA);
        distributor.acceptRoot(id, bytes32(uint256(1)));
        vm.expectRevert(IRewardsDistributor.TimelockNotExpired.selector);
        distributor.acceptRoot(otherId, bytes32(uint256(2)));
        vm.warp(validAtB);
        distributor.acceptRoot(otherId, bytes32(uint256(2)));
        assertEq(_root(id), bytes32(uint256(1)));
        assertEq(_root(otherId), bytes32(uint256(2)));
    }

    function testZeroTimelockAndZeroRoot() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, 0);
        _submit(otherId, bytes32(0));
        _submit(otherId, bytes32(0));
        distributor.acceptRoot(otherId, bytes32(0));
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.acceptRoot(otherId, bytes32(0));
    }

    function testResubmitRestartsOnlyThatRootsTimelock() public {
        bytes32 rootA = bytes32(uint256(1));
        bytes32 rootB = bytes32(uint256(2));
        _submit(id, rootA);
        _submit(id, rootB);
        uint256 firstValidAt = distributor.validAt(id, rootA);
        vm.warp(firstValidAt);
        vm.expectEmit(true, true, false, true);
        emit IRewardsDistributor.SubmitRoot(id, updater, rootA);
        _submit(id, rootA);
        assertEq(distributor.validAt(id, rootA), firstValidAt + TIMELOCK);
        vm.expectRevert(IRewardsDistributor.TimelockNotExpired.selector);
        distributor.acceptRoot(id, rootA);
        distributor.acceptRoot(id, rootB);
        assertEq(_root(id), rootB);
        vm.warp(firstValidAt + TIMELOCK);
        distributor.acceptRoot(id, rootA);
        assertEq(_root(id), rootA);
    }

    function testMultiplePendingRootsAndSpecificRevocation() public {
        bytes32 rootA = bytes32(uint256(1));
        bytes32 rootB = bytes32(uint256(2));
        bytes32 rootC = bytes32(uint256(3));
        _submit(id, rootA);
        _submit(id, rootB);
        _submit(id, rootC);
        uint256 validAt = distributor.validAt(id, rootA);
        vm.expectEmit(true, true, false, true);
        emit IRewardsDistributor.RevokePendingRoot(id, updater, rootB);
        vm.prank(updater);
        distributor.revokePendingRoot(id, rootB);
        assertEq(distributor.validAt(id, rootB), 0);
        assertEq(distributor.validAt(id, rootA), validAt);
        assertEq(distributor.validAt(id, rootC), validAt);
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.acceptRoot(id, rootB);
        vm.prank(updater);
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.revokePendingRoot(id, rootB);
        vm.warp(validAt);
        distributor.acceptRoot(id, rootC);
        assertEq(_root(id), rootC);
        assertEq(distributor.validAt(id, rootA), validAt);
        assertEq(distributor.validAt(id, rootC), 0);
        distributor.acceptRoot(id, rootA);
        assertEq(_root(id), rootA);
    }

    function testPauseAndTimelockedResume() public {
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        bytes32 root = merkle.getRoot(leaves);
        distributor.fund(id, 100);
        _activate(id, root);
        vm.expectEmit(true, true, false, true);
        emit IRewardsDistributor.PauseCampaign(id, updater);
        vm.prank(updater);
        distributor.pauseCampaign(id);
        assertEq(_root(id), bytes32(0));
        assertEq(_balance(id), 100);
        vm.expectRevert(IRewardsDistributor.RootNotSet.selector);
        distributor.claim(id, alice, 100, proof);
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.acceptRoot(id, root);
        _submit(id, root);
        uint256 resumeValidAt = distributor.validAt(id, root);
        vm.expectRevert(IRewardsDistributor.TimelockNotExpired.selector);
        distributor.acceptRoot(id, root);
        vm.warp(resumeValidAt);
        distributor.acceptRoot(id, root);
        distributor.claim(id, alice, 100, proof);
        assertEq(token.balanceOf(alice), 100);
    }

    function testPauseWithZeroTimelockAndSameBlockSubmission() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, 0);
        bytes32 rootA = bytes32(uint256(1));
        bytes32 rootB = bytes32(uint256(2));
        _submit(otherId, rootA);
        vm.prank(updater);
        distributor.pauseCampaign(otherId);
        _submit(otherId, rootB);
        distributor.acceptRoot(otherId, rootA);
        assertEq(_root(otherId), rootA);
        distributor.acceptRoot(otherId, rootB);
        assertEq(_root(otherId), rootB);
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.acceptRoot(otherId, rootA);
    }

    function testPendingRootsSurvivePause() public {
        bytes32 rootA = bytes32(uint256(1));
        bytes32 rootB = bytes32(uint256(2));
        _submit(id, rootA);
        uint256 firstValidAt = distributor.validAt(id, rootA);
        vm.warp(firstValidAt);
        _submit(id, rootB);
        uint256 secondValidAt = distributor.validAt(id, rootB);
        vm.prank(updater);
        distributor.pauseCampaign(id);
        assertEq(distributor.validAt(id, rootA), firstValidAt);
        assertEq(distributor.validAt(id, rootB), secondValidAt);
        vm.expectRevert(IRewardsDistributor.TimelockNotExpired.selector);
        distributor.acceptRoot(id, rootB);
        distributor.acceptRoot(id, rootA);
        assertEq(_root(id), rootA);
        vm.warp(secondValidAt);
        distributor.acceptRoot(id, rootB);
        assertEq(_root(id), rootB);
    }

    function testRevokePendingRootAfterPause() public {
        bytes32 root = bytes32(uint256(1));
        _submit(id, root);
        vm.warp(distributor.validAt(id, root));
        vm.startPrank(updater);
        distributor.pauseCampaign(id);
        distributor.revokePendingRoot(id, root);
        vm.stopPrank();
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.acceptRoot(id, root);
        assertEq(_root(id), bytes32(0));
    }

    function testAccessControl(address caller) public {
        vm.assume(caller != updater);
        _submit(id, bytes32(uint256(1)));
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(distributor.submitRoot, (id, bytes32(uint256(2))));
        calls[1] = abi.encodeCall(distributor.revokePendingRoot, (id, bytes32(uint256(1))));
        calls[2] = abi.encodeCall(distributor.pauseCampaign, (id));
        calls[3] = abi.encodeCall(distributor.setUpdater, (id, bob));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(caller);
            (bool success, bytes memory reason) = address(distributor).call(calls[i]);
            assertFalse(success);
            assertEq(reason, abi.encodeWithSelector(IRewardsDistributor.NotUpdater.selector));
        }
    }

    function testSetUpdater() public {
        vm.startPrank(updater);
        vm.expectRevert(IRewardsDistributor.AlreadySet.selector);
        distributor.setUpdater(id, updater);
        vm.expectEmit(true, true, false, true);
        emit IRewardsDistributor.SetUpdater(id, bob);
        distributor.setUpdater(id, bob);
        vm.expectRevert(IRewardsDistributor.NotUpdater.selector);
        distributor.submitRoot(id, bytes32(uint256(1)));
        vm.stopPrank();
        vm.prank(bob);
        distributor.submitRoot(id, bytes32(uint256(1)));
    }

    function testCumulativeClaims(uint128 first, uint128 increment) public {
        uint256 amount = bound(first, 1, type(uint128).max);
        uint256 total = amount + bound(increment, 1, type(uint128).max);
        token.mint(address(this), total);
        distributor.fund(id, total);
        bytes32[] memory leaves = _tree(address(token), amount);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        _activate(id, merkle.getRoot(leaves));
        vm.expectEmit(true, true, false, true);
        emit IRewardsDistributor.Claim(id, alice, amount);
        vm.prank(bob);
        assertEq(distributor.claim(id, alice, amount, proof), amount);
        vm.expectRevert(IRewardsDistributor.ClaimableTooLow.selector);
        distributor.claim(id, alice, amount, proof);
        leaves = _tree(address(token), total);
        proof = merkle.getProof(leaves, 0);
        _activate(id, merkle.getRoot(leaves));
        assertEq(distributor.claim(id, alice, total, proof), total - amount);
        assertEq(token.balanceOf(alice), total);
        assertEq(distributor.claimed(id, alice), total);
        assertEq(_balance(id), 0);
        leaves = _tree(address(token), amount);
        proof = merkle.getProof(leaves, 0);
        _activate(id, merkle.getRoot(leaves));
        vm.expectRevert(IRewardsDistributor.ClaimableTooLow.selector);
        distributor.claim(id, alice, amount, proof);
    }

    function testInvalidProofAndUnsetRoot() public {
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        vm.expectRevert(IRewardsDistributor.RootNotSet.selector);
        distributor.claim(id, alice, 100, proof);
        _activate(id, merkle.getRoot(leaves));
        vm.expectRevert(IRewardsDistributor.InvalidProofOrExpired.selector);
        distributor.claim(id, alice, 101, proof);
        vm.expectRevert(IRewardsDistributor.InvalidProofOrExpired.selector);
        distributor.claim(id, bob, 100, proof);
        vm.expectRevert(IRewardsDistributor.InvalidProofOrExpired.selector);
        distributor.claim(id, alice, 100, new bytes32[](0));
        assertEq(distributor.claimed(id, alice), 0);
    }

    function testZeroClaimable() public {
        bytes32[] memory leaves = _tree(address(token), 0);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        _activate(id, merkle.getRoot(leaves));
        vm.expectRevert(IRewardsDistributor.ClaimableTooLow.selector);
        distributor.claim(id, alice, 0, proof);
    }

    function testUnknownCampaigns(uint256 unknown) public {
        vm.assume(unknown != id);
        bytes[] memory calls = new bytes[](7);
        calls[0] = abi.encodeCall(distributor.fund, (unknown, 1));
        calls[1] = abi.encodeCall(distributor.submitRoot, (unknown, bytes32(uint256(1))));
        calls[2] = abi.encodeCall(distributor.acceptRoot, (unknown, bytes32(uint256(1))));
        calls[3] = abi.encodeCall(distributor.revokePendingRoot, (unknown, bytes32(uint256(1))));
        calls[4] = abi.encodeCall(distributor.pauseCampaign, (unknown));
        calls[5] = abi.encodeCall(distributor.setUpdater, (unknown, bob));
        calls[6] = abi.encodeCall(distributor.claim, (unknown, alice, 1, new bytes32[](0)));
        bytes4[] memory errors = new bytes4[](7);
        errors[0] = IRewardsDistributor.UnknownCampaign.selector;
        errors[1] = IRewardsDistributor.NotUpdater.selector;
        errors[2] = IRewardsDistributor.NoPendingRoot.selector;
        errors[3] = IRewardsDistributor.NotUpdater.selector;
        errors[4] = IRewardsDistributor.NotUpdater.selector;
        errors[5] = IRewardsDistributor.NotUpdater.selector;
        errors[6] = IRewardsDistributor.RootNotSet.selector;
        for (uint256 i; i < calls.length; ++i) {
            (bool success, bytes memory reason) = address(distributor).call(calls[i]);
            assertFalse(success);
            assertEq(reason, abi.encodeWithSelector(errors[i]));
        }
    }

    function testMulticallSubmissionsAndAcceptances() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, TIMELOCK);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(distributor.submitRoot, (id, bytes32(uint256(1))));
        calls[1] = abi.encodeCall(distributor.submitRoot, (otherId, bytes32(uint256(2))));
        vm.prank(updater);
        distribution.multicall(calls);
        uint256 validAt = distributor.validAt(id, bytes32(uint256(1)));
        assertGt(validAt, 0);
        assertEq(distributor.validAt(otherId, bytes32(uint256(2))), validAt);
        calls[0] = abi.encodeCall(distributor.acceptRoot, (id, bytes32(uint256(1))));
        calls[1] = abi.encodeCall(distributor.acceptRoot, (otherId, bytes32(uint256(2))));
        vm.expectRevert(IRewardsDistributor.TimelockNotExpired.selector);
        distributor.multicall(calls);
        vm.warp(validAt);
        vm.prank(bob);
        distributor.multicall(calls);
        assertEq(_root(id), bytes32(uint256(1)));
        assertEq(_root(otherId), bytes32(uint256(2)));
        assertEq(distributor.multicall(new bytes[](0)).length, 0);
    }

    function testTransferFailureRollsBackClaim() public {
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        distributor.fund(id, 100);
        _activate(id, merkle.getRoot(leaves));
        vm.mockCallRevert(
            address(token), abi.encodeWithSelector(token.transfer.selector, alice, 100), bytes("transfer failed")
        );
        vm.expectRevert(bytes(ErrorsLib.TRANSFER_REVERTED));
        distributor.claim(id, alice, 100, proof);
        assertEq(distributor.claimed(id, alice), 0);
        assertEq(_balance(id), 100);
    }

    function testMulticallReturnDataAndRollback() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(distributor.createCampaign, (address(token), updater, TIMELOCK));
        calls[1] = abi.encodeCall(distributor.campaignCount, ());
        bytes[] memory results = distributor.multicall(calls);
        assertEq(abi.decode(results[0], (uint256)), 2);
        assertEq(abi.decode(results[1], (uint256)), 2);

        calls[0] = abi.encodeCall(distributor.submitRoot, (id, bytes32(uint256(1))));
        calls[1] = abi.encodeCall(distributor.acceptRoot, (3, bytes32(uint256(1))));
        vm.prank(updater);
        vm.expectRevert(IRewardsDistributor.NoPendingRoot.selector);
        distributor.multicall(calls);
        assertEq(distributor.validAt(id, bytes32(uint256(1))), 0);
    }

    function testFundingFailureDoesNotCreditBalance() public {
        vm.prank(bob);
        vm.expectRevert();
        distributor.fund(id, 100);
        assertEq(_balance(id), 0);
    }

    function testFundingRejectsTokenWithoutCode() public {
        address noCodeToken = makeAddr("no code token");
        uint256 otherId = distributor.createCampaign(noCodeToken, updater, TIMELOCK);
        vm.expectRevert(bytes(ErrorsLib.NO_CODE));
        distributor.fund(otherId, 100);
        assertEq(_balance(otherId), 0);
    }

    function testTransferReturningFalseRollsBackClaim() public {
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        distributor.fund(id, 100);
        _activate(id, merkle.getRoot(leaves));
        vm.mockCall(address(token), abi.encodeWithSelector(token.transfer.selector, alice, 100), abi.encode(false));
        vm.expectRevert(bytes(ErrorsLib.TRANSFER_RETURNED_FALSE));
        distributor.claim(id, alice, 100, proof);
        assertEq(distributor.claimed(id, alice), 0);
        assertEq(_balance(id), 100);
    }

    function testSingleLeafEmptyProof() public {
        bytes32 root = keccak256(bytes.concat(keccak256(abi.encode(alice, address(token), uint256(100)))));
        distributor.fund(id, 100);
        _activate(id, root);
        distributor.claim(id, alice, 100, new bytes32[](0));
        assertEq(token.balanceOf(alice), 100);
    }

    function testMultipleLevelSortedProof(uint128 claimable) public {
        uint256 amount = bound(claimable, 1, type(uint128).max);
        bytes32[] memory leftLeaves = _tree(address(token), amount);
        bytes32[] memory rightLeaves = _tree(address(token), amount + 1);
        bytes32[] memory parents = new bytes32[](2);
        parents[0] = merkle.getRoot(leftLeaves);
        parents[1] = merkle.getRoot(rightLeaves);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leftLeaves[1];
        proof[1] = parents[1];
        token.mint(address(this), amount);
        distributor.fund(id, amount);
        _activate(id, merkle.getRoot(parents));
        distributor.claim(id, alice, amount, proof);
        assertEq(token.balanceOf(alice), amount);
        assertEq(_balance(id), 0);
    }
}
