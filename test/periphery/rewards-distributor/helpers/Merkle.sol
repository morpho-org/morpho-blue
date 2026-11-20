// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Sorted-pair Merkle helper for the two-recipient test trees.
contract Merkle {
    function getRoot(bytes32[] memory leaves) external pure returns (bytes32) {
        require(leaves.length == 2);
        return leaves[0] < leaves[1]
            ? keccak256(abi.encodePacked(leaves[0], leaves[1]))
            : keccak256(abi.encodePacked(leaves[1], leaves[0]));
    }

    function getProof(bytes32[] memory leaves, uint256 index) external pure returns (bytes32[] memory proof) {
        require(leaves.length == 2 && index < 2);
        proof = new bytes32[](1);
        proof[0] = leaves[1 - index];
    }
}
