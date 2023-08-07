// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationGetterTest is BlueBaseTest {
    function testExtsLoad(uint256 slot, bytes32 value0) public {
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = bytes32(slot);
        slots[1] = bytes32(slot / 2);

        bytes32 value1 = keccak256(abi.encode(value0));
        vm.store(address(blue), slots[0], value0);
        vm.store(address(blue), slots[1], value1);

        bytes32[] memory values = blue.extsload(slots);

        assertEq(values.length, 2, "values.length");
        assertEq(values[0], slot > 0 ? value0 : value1, "value0");
        assertEq(values[1], value1, "value1");
    }
}
