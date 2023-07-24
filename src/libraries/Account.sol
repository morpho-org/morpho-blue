// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Account {
    bytes32 constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    function getAddress(bytes32 self) internal pure returns (address res) {
        assembly {
            res := and(self, ADDRESS_MASK)
        }
    }

    function getNonce(bytes32 self) internal pure returns (uint256 res) {
        assembly {
            res := shr(160, self)
        }
    }

    function account(address user, uint96 nonce) internal pure returns (bytes32 res) {
        assembly {
            res := or(user, shl(160, nonce))
        }
    }
}
