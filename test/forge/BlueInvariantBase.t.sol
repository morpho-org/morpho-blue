// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract InvariantBaseTest is BlueBaseTest {
    using FixedPointMathLib for uint256;

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

    function sumUsersSupplyShares(address[] memory addresses) internal view returns(uint256) {
        uint256 sum;
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.supplyShares(id, addresses[i]);
        }
        return sum;
    }

    function sumUsersBorrowShares(address[] memory addresses) internal view returns(uint256) {
        uint256 sum;
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.borrowShares(id, addresses[i]);
        }
        return sum;
    }
}