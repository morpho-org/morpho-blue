// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "../../../lib/forge-std/src/Test.sol";
import {Merkle} from "./helpers/Merkle.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {RewardsDistributor} from "../../../src/periphery/rewards-distributor/RewardsDistributor.sol";
import {IRewardsDistributor} from "../../../src/periphery/rewards-distributor/interfaces/IRewardsDistributor.sol";
import {ErrorsLib} from "../../../src/periphery/rewards-distributor/libraries/ErrorsLib.sol";
import {EventsLib} from "../../../src/periphery/rewards-distributor/libraries/EventsLib.sol";

contract RewardsToken is ERC20Mock {
    function mint(address account, uint256 amount) external {
        setBalance(account, balanceOf[account] + amount);
    }
}

contract FeeToken is RewardsToken {
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = amount / 10;
        setBalance(msg.sender, balanceOf[msg.sender] - fee);
        return super.transfer(to, amount - fee);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 beforeBalance = balanceOf[to];
        super.transferFrom(from, to, amount);
        setBalance(to, beforeBalance + amount - amount / 10);
        return true;
    }
}

contract CallbackToken is RewardsToken {
    address internal target;
    bytes internal callback;

    function configure(address target_, bytes calldata callback_) external {
        target = target_;
        callback = callback_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        _callback();
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        _callback();
        return true;
    }

    function _callback() internal {
        if (target != address(0)) {
            (bool success, bytes memory result) = target.call(callback);
            require(!success && keccak256(result) == keccak256(abi.encodeWithSignature("Error(string)", "REENTRANCY")));
        }
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
        (, uint256 validAt) = distributor.pendingRoot(campaignId);
        vm.warp(validAt);
        distributor.acceptRoot(campaignId);
    }

    function testCreateCampaign(address creator, uint256 timelock) public {
        vm.expectEmit(true, true, true, true);
        emit EventsLib.CampaignCreated(2, creator, address(token), updater, timelock);
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

    function testCreateRejectsZeroAddresses() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        distributor.createCampaign(address(0), updater, 0);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        distributor.createCampaign(address(token), address(0), 0);
    }

    function testFund(uint128 amount) public {
        token.mint(bob, amount);
        vm.prank(bob);
        token.approve(address(distributor), amount);
        vm.expectEmit(true, true, false, true);
        emit EventsLib.Funded(id, bob, amount);
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
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_BALANCE));
        distributor.claim(id, alice, 100, proof);
        distributor.fund(id, 40);
        assertEq(_balance(id), 40);
        assertEq(token.balanceOf(address(distributor)), 140);
    }

    function testFeeOnTransferCreditsActualReceipts(uint128 amount) public {
        FeeToken feeToken = new FeeToken();
        uint256 feeId = distributor.createCampaign(address(feeToken), updater, TIMELOCK);
        feeToken.mint(address(this), amount);
        feeToken.approve(address(distributor), amount);
        uint256 received = uint256(amount) - uint256(amount) / 10;
        vm.expectEmit(true, true, false, true);
        emit EventsLib.Funded(feeId, address(this), received);
        distributor.fund(feeId, amount);
        assertEq(_balance(feeId), received);
        assertEq(feeToken.balanceOf(address(distributor)), received);
        if (received == 0) return;
        bytes32[] memory leaves = _tree(address(feeToken), received);
        _activate(feeId, merkle.getRoot(leaves));
        distributor.claim(feeId, alice, received, merkle.getProof(leaves, 0));
        assertEq(_balance(feeId), 0);
        assertEq(feeToken.balanceOf(alice), received - received / 10);
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
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_BALANCE));
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
        (, uint256 validAt) = distributor.pendingRoot(id);
        assertEq(validAt, block.timestamp + TIMELOCK);
        vm.warp(validAt - 1);
        vm.expectRevert(bytes(ErrorsLib.TIMELOCK_NOT_EXPIRED));
        distributor.acceptRoot(id);
        vm.warp(validAt);
        vm.expectEmit(true, false, false, true);
        emit EventsLib.RootSet(id, root);
        vm.prank(caller);
        distributor.acceptRoot(id);
        assertEq(_root(id), root);
        (bytes32 pending, uint256 timestamp) = distributor.pendingRoot(id);
        assertEq(pending, bytes32(0));
        assertEq(timestamp, 0);
        vm.expectRevert(bytes(ErrorsLib.NO_PENDING_ROOT));
        distributor.acceptRoot(id);
    }

    function testIndependentTimelocks() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, 2 * TIMELOCK);
        _submit(id, bytes32(uint256(1)));
        _submit(otherId, bytes32(uint256(2)));
        (, uint256 validAtA) = distributor.pendingRoot(id);
        (, uint256 validAtB) = distributor.pendingRoot(otherId);
        assertEq(validAtB, validAtA + TIMELOCK);
        vm.warp(validAtA);
        distributor.acceptRoot(id);
        vm.expectRevert(bytes(ErrorsLib.TIMELOCK_NOT_EXPIRED));
        distributor.acceptRoot(otherId);
        vm.warp(validAtB);
        distributor.acceptRoot(otherId);
        assertEq(_root(id), bytes32(uint256(1)));
        assertEq(_root(otherId), bytes32(uint256(2)));
    }

    function testZeroTimelockAndZeroRoot() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, 0);
        _submit(otherId, bytes32(0));
        vm.expectRevert(bytes(ErrorsLib.ALREADY_PENDING));
        _submit(otherId, bytes32(0));
        distributor.acceptRoot(otherId);
        vm.expectRevert(bytes(ErrorsLib.NO_PENDING_ROOT));
        distributor.acceptRoot(otherId);
    }

    function testReplaceAndRevokePendingRoot() public {
        _submit(id, bytes32(uint256(1)));
        vm.expectRevert(bytes(ErrorsLib.ALREADY_PENDING));
        _submit(id, bytes32(uint256(1)));
        (, uint256 firstValidAt) = distributor.pendingRoot(id);
        vm.warp(firstValidAt);
        _submit(id, bytes32(uint256(2)));
        vm.expectRevert(bytes(ErrorsLib.TIMELOCK_NOT_EXPIRED));
        distributor.acceptRoot(id);
        vm.expectEmit(true, true, false, true);
        emit EventsLib.PendingRootRevoked(id, updater);
        vm.prank(updater);
        distributor.revokePendingRoot(id);
        (bytes32 root, uint256 validAt) = distributor.pendingRoot(id);
        assertEq(root, bytes32(0));
        assertEq(validAt, 0);
        vm.expectRevert(bytes(ErrorsLib.NO_PENDING_ROOT));
        distributor.acceptRoot(id);
        vm.prank(updater);
        vm.expectRevert(bytes(ErrorsLib.NO_PENDING_ROOT));
        distributor.revokePendingRoot(id);
    }

    function testPauseAndTimelockedResume() public {
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        bytes32 root = merkle.getRoot(leaves);
        distributor.fund(id, 100);
        _activate(id, root);
        _submit(id, bytes32(uint256(1)));
        (, uint256 revokedValidAt) = distributor.pendingRoot(id);
        vm.expectEmit(true, true, false, true);
        emit EventsLib.CampaignPaused(id, updater);
        vm.prank(updater);
        distributor.pauseCampaign(id);
        assertEq(_root(id), bytes32(0));
        assertEq(_balance(id), 100);
        (, uint256 validAt) = distributor.pendingRoot(id);
        assertEq(validAt, 0);
        vm.expectRevert(bytes(ErrorsLib.ROOT_NOT_SET));
        distributor.claim(id, alice, 100, proof);
        vm.warp(revokedValidAt);
        vm.expectRevert(bytes(ErrorsLib.NO_PENDING_ROOT));
        distributor.acceptRoot(id);
        _submit(id, root);
        (, uint256 resumeValidAt) = distributor.pendingRoot(id);
        vm.expectRevert(bytes(ErrorsLib.TIMELOCK_NOT_EXPIRED));
        distributor.acceptRoot(id);
        vm.warp(resumeValidAt);
        distributor.acceptRoot(id);
        distributor.claim(id, alice, 100, proof);
        assertEq(token.balanceOf(alice), 100);
    }

    function testAccessControl(address caller) public {
        vm.assume(caller != updater);
        _submit(id, bytes32(uint256(1)));
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(distributor.submitRoot, (id, bytes32(uint256(2))));
        calls[1] = abi.encodeCall(distributor.revokePendingRoot, (id));
        calls[2] = abi.encodeCall(distributor.pauseCampaign, (id));
        calls[3] = abi.encodeCall(distributor.setUpdater, (id, bob));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(caller);
            (bool success, bytes memory reason) = address(distributor).call(calls[i]);
            assertFalse(success);
            assertEq(reason, abi.encodeWithSignature("Error(string)", ErrorsLib.NOT_UPDATER_ROLE));
        }
    }

    function testSetUpdater() public {
        vm.startPrank(updater);
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        distributor.setUpdater(id, address(0));
        vm.expectRevert(bytes(ErrorsLib.ALREADY_SET));
        distributor.setUpdater(id, updater);
        vm.expectEmit(true, true, false, true);
        emit EventsLib.UpdaterSet(id, bob);
        distributor.setUpdater(id, bob);
        vm.expectRevert(bytes(ErrorsLib.NOT_UPDATER_ROLE));
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
        emit EventsLib.Claimed(id, alice, amount);
        vm.prank(bob);
        assertEq(distributor.claim(id, alice, amount, proof), amount);
        vm.expectRevert(bytes(ErrorsLib.CLAIMABLE_TOO_LOW));
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
        vm.expectRevert(bytes(ErrorsLib.CLAIMABLE_TOO_LOW));
        distributor.claim(id, alice, amount, proof);
    }

    function testInvalidProofAndUnsetRoot() public {
        bytes32[] memory leaves = _tree(address(token), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        vm.expectRevert(bytes(ErrorsLib.ROOT_NOT_SET));
        distributor.claim(id, alice, 100, proof);
        _activate(id, merkle.getRoot(leaves));
        vm.expectRevert(bytes(ErrorsLib.INVALID_PROOF_OR_EXPIRED));
        distributor.claim(id, alice, 101, proof);
        vm.expectRevert(bytes(ErrorsLib.INVALID_PROOF_OR_EXPIRED));
        distributor.claim(id, bob, 100, proof);
        vm.expectRevert(bytes(ErrorsLib.INVALID_PROOF_OR_EXPIRED));
        distributor.claim(id, alice, 100, new bytes32[](0));
        assertEq(distributor.claimed(id, alice), 0);
    }

    function testZeroClaimable() public {
        bytes32[] memory leaves = _tree(address(token), 0);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        _activate(id, merkle.getRoot(leaves));
        vm.expectRevert(bytes(ErrorsLib.CLAIMABLE_TOO_LOW));
        distributor.claim(id, alice, 0, proof);
    }

    function testUnknownCampaigns(uint256 unknown) public {
        vm.assume(unknown != id);
        bytes[] memory calls = new bytes[](7);
        calls[0] = abi.encodeCall(distributor.fund, (unknown, 1));
        calls[1] = abi.encodeCall(distributor.submitRoot, (unknown, bytes32(uint256(1))));
        calls[2] = abi.encodeCall(distributor.acceptRoot, (unknown));
        calls[3] = abi.encodeCall(distributor.revokePendingRoot, (unknown));
        calls[4] = abi.encodeCall(distributor.pauseCampaign, (unknown));
        calls[5] = abi.encodeCall(distributor.setUpdater, (unknown, bob));
        calls[6] = abi.encodeCall(distributor.claim, (unknown, alice, 1, new bytes32[](0)));
        for (uint256 i; i < calls.length; ++i) {
            (bool success, bytes memory reason) = address(distributor).call(calls[i]);
            assertFalse(success);
            assertEq(reason, abi.encodeWithSignature("Error(string)", ErrorsLib.UNKNOWN_CAMPAIGN));
        }
    }

    function testMulticallSubmissionsAndAcceptances() public {
        uint256 otherId = distributor.createCampaign(address(token), updater, TIMELOCK);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(distributor.submitRoot, (id, bytes32(uint256(1))));
        calls[1] = abi.encodeCall(distributor.submitRoot, (otherId, bytes32(uint256(2))));
        vm.prank(updater);
        distribution.multicall(calls);
        (bytes32 pendingA, uint256 validAt) = distributor.pendingRoot(id);
        (bytes32 pendingB,) = distributor.pendingRoot(otherId);
        assertEq(pendingA, bytes32(uint256(1)));
        assertEq(pendingB, bytes32(uint256(2)));
        calls[0] = abi.encodeCall(distributor.acceptRoot, (id));
        calls[1] = abi.encodeCall(distributor.acceptRoot, (otherId));
        vm.expectRevert(bytes(ErrorsLib.TIMELOCK_NOT_EXPIRED));
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
        vm.expectRevert(bytes("TRANSFER_FAILED"));
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
        calls[1] = abi.encodeCall(distributor.acceptRoot, (3));
        vm.prank(updater);
        vm.expectRevert(bytes(ErrorsLib.UNKNOWN_CAMPAIGN));
        distributor.multicall(calls);
        (bytes32 root, uint256 validAt) = distributor.pendingRoot(id);
        assertEq(root, bytes32(0));
        assertEq(validAt, 0);
    }

    function testFundingFailureDoesNotCreditBalance() public {
        vm.prank(bob);
        vm.expectRevert();
        distributor.fund(id, 100);
        assertEq(_balance(id), 0);
    }

    function testReentrancyGuardOnFundAndClaim() public {
        CallbackToken callbackToken = new CallbackToken();
        uint256 callbackId = distributor.createCampaign(address(callbackToken), updater, 0);
        callbackToken.mint(address(this), 200);
        callbackToken.approve(address(distributor), 200);
        bytes32[] memory leaves = _tree(address(callbackToken), 100);
        bytes32[] memory proof = merkle.getProof(leaves, 0);
        _activate(callbackId, merkle.getRoot(leaves));
        bytes[] memory callbacks = new bytes[](2);
        callbacks[0] = abi.encodeCall(distributor.fund, (callbackId, 0));
        callbacks[1] = abi.encodeCall(distributor.claim, (callbackId, alice, 100, proof));
        for (uint256 i; i < callbacks.length; ++i) {
            callbackToken.configure(address(distributor), callbacks[i]);
            distributor.fund(callbackId, 100);
            assertEq(_balance(callbackId), 100 * (i + 1));
            assertEq(callbackToken.balanceOf(address(distributor)), 100 * (i + 1));
        }
        for (uint256 i; i < callbacks.length; ++i) {
            address account = i == 0 ? alice : bob;
            bytes32[] memory accountProof = merkle.getProof(leaves, i);
            callbackToken.configure(address(distributor), callbacks[i]);
            distributor.claim(callbackId, account, 100, accountProof);
            assertEq(_balance(callbackId), 100 * (1 - i));
            assertEq(distributor.claimed(callbackId, account), 100);
        }
    }
}
