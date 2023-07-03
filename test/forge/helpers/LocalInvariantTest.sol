// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/LocalTest.sol";

contract LocalInvariantTest is LocalTest {
    bytes4[] internal selectors;

    function setUp() public virtual override {
        super.setUp();

        targetContract(address(this));
    }

    function _targetDefaultSenders() internal {
        targetSender(0x1000000000000000000000000000000000000000);
        targetSender(0x0100000000000000000000000000000000000000);
        targetSender(0x0010000000000000000000000000000000000000);
        targetSender(0x0001000000000000000000000000000000000000);
        targetSender(0x0000100000000000000000000000000000000000);
        targetSender(0x0000010000000000000000000000000000000000);
        targetSender(0x0000001000000000000000000000000000000000);
        targetSender(0x0000000100000000000000000000000000000000);
    }

    function _weightSelector(bytes4 selector, uint256 weight) internal {
        for (uint256 i; i < weight; ++i) {
            selectors.push(selector);
        }
    }

    function _randomSender(address seed) internal view returns (address) {
        address[] memory senders = targetSenders();

        return senders[uint256(uint160(seed)) % senders.length];
    }
}
