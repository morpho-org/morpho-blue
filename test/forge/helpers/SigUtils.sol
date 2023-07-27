// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {EIP712_AUTHORIZATION_TYPEHASH} from "src/Blue.sol";

contract SigUtils {
    struct Authorization {
        address delegator;
        address manager;
        bool isAllowed;
        uint256 nonce;
        uint256 deadline;
    }

    bytes32 internal domainSeparator;

    constructor(bytes32 _domainSeparator) {
        domainSeparator = _domainSeparator;
    }

    /// @dev Computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Authorization memory authorization) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, getStructHash(authorization)));
    }

    function getStructHash(Authorization memory authorization) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_AUTHORIZATION_TYPEHASH,
                authorization.delegator,
                authorization.manager,
                authorization.isAllowed,
                authorization.nonce,
                authorization.deadline
            )
        );
    }
}
