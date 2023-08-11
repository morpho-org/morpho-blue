// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Authorization, AUTHORIZATION_TYPEHASH} from "src/Blue.sol";

library SigUtils {
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
                authorization.authorizer,
                authorization.authorized,
                authorization.isAuthorized,
                authorization.nonce,
                authorization.deadline
            )
        );
    }
}
