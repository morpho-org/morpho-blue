// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract IntegrationGetterTest is BaseTest {
    function testExtsLoad(uint256 slot, bytes32 value0) public {
        uint256[] memory slots = new uint256[](2);
        slots[0] = slot;
        slots[1] = slot / 2;

        bytes32 value1 = keccak256(abi.encode(value0));
        vm.store(address(morpho), bytes32(slots[0]), value0);
        vm.store(address(morpho), bytes32(slots[1]), value1);

        bytes32[] memory values = morpho.sloads(slots);

        assertEq(values.length, 2, "values.length");
        assertEq(values[0], slot > 0 ? value0 : value1, "value0");
        assertEq(values[1], value1, "value1");
    }
}
