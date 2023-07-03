// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/libraries/Types.sol";
import "src/libraries/Errors.sol";
import "src/libraries/Constants.sol";
import {Events} from "src/libraries/Events.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {Morpho} from "src/Morpho.sol";

import {stdStorage, StdStorage} from "@forge-std/StdStorage.sol";
import {console2} from "@forge-std/console2.sol";
import {console} from "@forge-std/console.sol";
import {Test} from "@forge-std/Test.sol";

contract BaseTest is Test {
    uint256 internal constant BLOCK_TIME = 12;

    /// @dev Asserts a is approximately less than or equal to b, with a maximum absolute difference of maxDelta.
    function assertApproxLeAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal {
        assertLe(a, b, err);
        assertApproxEqAbs(a, b, maxDelta, err);
    }

    /// @dev Asserts a is approximately greater than or equal to b, with a maximum absolute difference of maxDelta.
    function assertApproxGeAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal {
        assertGe(a, b, err);
        assertApproxEqAbs(a, b, maxDelta, err);
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_TIME); // Block speed should depend on test network.
    }

    /// @dev Bounds the fuzzing input to a realistic number of blocks.
    function _boundBlocks(uint256 blocks) internal view returns (uint256) {
        return bound(blocks, 1, type(uint24).max);
    }

    /// @dev Bounds the fuzzing input to a non-zero 256 bits unsigned integer.
    function _boundNotZero(uint256 input) internal view virtual returns (uint256) {
        return bound(input, 1, type(uint256).max);
    }

    /// @dev Bounds the fuzzing input to a non-zero address.
    function _boundAddressNotZero(address input) internal view virtual returns (address) {
        return address(uint160(bound(uint256(uint160(input)), 1, type(uint160).max)));
    }

    /// @dev Assumes the receiver is able to receive ETH without reverting.
    function _assumeETHReceiver(address receiver) internal virtual {
        (bool success,) = receiver.call("");
        vm.assume(success);
    }

    /// @dev Returns true if `addrs` contains `addr`, and false otherwise.
    function _contains(address[] memory addrs, address addr) internal pure returns (bool) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] == addr) {
                return true;
            }
        }
        return false;
    }
}
