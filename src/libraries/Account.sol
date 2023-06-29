// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Account {
    bytes32 constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    function addr(bytes32 self) internal pure returns (address res) {
        assembly {
            res := and(self, ADDRESS_MASK)
        }
    }

    function lltv(bytes32 self) internal pure returns (uint256 res) {
        assembly {
            res := and(shr(160, self), 0xff)
        }
        res *= 1e16;
    }

    function nonce(bytes32 self) internal pure returns (uint256 res) {
        assembly {
            res := shr(168, self)
        }
    }

    function account(address _addr, uint8 _lltv, uint88 _nonce) internal pure returns (bytes32 res) {
        assembly {
            res := or(or(_addr, shl(160, _lltv)), shl(168, _nonce))
        }
    }
}
