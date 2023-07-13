// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Constants.
library Constants {
    /// @dev 1 wad.
    uint256 internal constant WAD = 1e18;

    /// @dev Scaling factor for the liquidation incentive.
    uint256 internal constant ALPHA = 0.5e18;

    /// @dev The prefix used for EIP-712 signature.
    string internal constant EIP712_MSG_PREFIX = "\x19\x01";

    /// @dev The name used for EIP-712 signature.
    string internal constant EIP712_NAME = "Blue";

    /// @dev The domain typehash used for the EIP-712 signature.
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @dev The typehash for approveManagerWithSig Authorization used for the EIP-712 signature.
    bytes32 internal constant EIP712_AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address delegator,address manager,bool isAllowed,uint256 nonce,uint256 deadline)");

    /// @dev The highest valid value for s in an ECDSA signature pair (0 < s < secp256k1n ÷ 2 + 1).
    uint256 internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
}
