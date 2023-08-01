// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @dev The EIP-712 typeHash for EIP712Domain.
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

/// @dev The EIP-712 typeHash for Authorization.
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");

struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

library AuthorizationLib {
    /// @dev Computes the EIP712 domain separator.
    function domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Blue"), block.chainid, address(this)));
    }

    /// @dev Computes the EIP712 typed authorization hash to be signed.
    function hashAuthorization(
        bytes32 _domainSeparator,
        address authorizer,
        address authorized,
        bool isAuthorized,
        uint256 deadline,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator,
                keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorizer, authorized, isAuthorized, nonce, deadline))
            )
        );
    }
}
