// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

library Constants {
    uint256 internal constant TRANCHE_NUMBER = 16;
    uint256 internal constant ALPHA = 10; // To Define for liquidation

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @dev The domain typehash used for the EIP-712 signature.
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev The typehash for approveManagerWithSig Authorization used for the EIP-712 signature.
    bytes32 internal constant EIP712_AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address delegator,address manager,bool isAllowed,uint256 nonce,uint256 deadline)");
    uint256 internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @dev The prefix used for EIP-712 signature.
    string internal constant EIP712_MSG_PREFIX = "\x19\x01";

    /// @dev The name used for EIP-712 signature.
    string internal constant EIP712_NAME = "Morpho-AaveV3";

    /// @dev The version used for EIP-712 signature.
    string internal constant EIP712_VERSION = "0";
}
