// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SigUtils} from "test/forge/helpers/SigUtils.sol";

import "../BaseTest.sol";

contract IntegrationAuthorization is BaseTest {
    function testSetAuthorization(address addressFuzz) public {
        vm.assume(addressFuzz != address(this));

        morpho.setAuthorization(addressFuzz, true);

        assertTrue(morpho.isAuthorized(address(this), addressFuzz));

        morpho.setAuthorization(addressFuzz, false);

        assertFalse(morpho.isAuthorized(address(this), addressFuzz));
    }

    function testSetAuthorizationWithSignatureDeadlineOutdated(
        Authorization memory authorization,
        uint256 privateKey,
        uint256 elapsed
    ) public {
        elapsed = bound(elapsed, 1, type(uint32).max);
        authorization.deadline = block.timestamp;

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.nonce = 0;
        authorization.authorizer = vm.addr(privateKey);

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);

        vm.expectRevert(bytes(ErrorsLib.SIGNATURE_EXPIRED));
        morpho.setAuthorizationWithSig(authorization, sig);
    }

    function testAuthorizationWithSigWrongPK(Authorization memory authorization, uint256 privateKey) public {
        vm.assume(authorization.deadline > block.timestamp);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.nonce = 0;

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(bytes(ErrorsLib.INVALID_SIGNATURE));
        morpho.setAuthorizationWithSig(authorization, sig);
    }

    function testAuthorizationWithSigWrongNonce(Authorization memory authorization, uint256 privateKey) public {
        vm.assume(authorization.deadline > block.timestamp);
        vm.assume(authorization.nonce != 0);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.authorizer = vm.addr(privateKey);

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(bytes(ErrorsLib.INVALID_NONCE));
        morpho.setAuthorizationWithSig(authorization, sig);
    }

    function testAuthorizationWithSig(Authorization memory authorization, uint256 privateKey) public {
        vm.assume(authorization.deadline > block.timestamp);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        authorization.nonce = 0;
        authorization.authorizer = vm.addr(privateKey);

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        morpho.setAuthorizationWithSig(authorization, sig);

        assertEq(morpho.isAuthorized(authorization.authorizer, authorization.authorized), authorization.isAuthorized);
        assertEq(morpho.nonce(authorization.authorizer), 1);
    }
}
