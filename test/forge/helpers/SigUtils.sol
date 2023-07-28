// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AUTHORIZATION_TYPEHASH} from "src/Blue.sol";

library SigUtils {
    struct Authorization {
        address delegator;
        address manager;
        bool isAllowed;
        uint256 nonce;
        uint256 deadline;
    }

    /// @dev Computes the hash of the EIP-712 encoded data.
    function getTypedDataHash(bytes32 domainSeparator, Authorization memory authorization)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashStruct(authorization)));
    }

    function hashStruct(Authorization memory authorization) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                AUTHORIZATION_TYPEHASH,
                authorization.delegator,
                authorization.manager,
                authorization.isAllowed,
                authorization.nonce,
                authorization.deadline
            )
        );
    }
}
