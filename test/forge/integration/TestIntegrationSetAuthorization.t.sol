// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SigUtils} from "../helpers/SigUtils.sol";

import "../BaseTest.sol";

contract IntegrationAuthorization is BaseTest {
    function testSetAuthorization(address addressFuzz) public {
        vm.assume(addressFuzz != address(this));

        blue.setAuthorization(addressFuzz, true);

        assertTrue(blue.isAuthorized(address(this), addressFuzz));

        blue.setAuthorization(addressFuzz, false);

        assertFalse(blue.isAuthorized(address(this), addressFuzz));
    }

    function testSetAuthorizationWithSignatureDeadlineOutdated(
        uint32 deadline,
        address authorized,
        uint256 privateKey,
        bool isAuthorized,
        uint256 timeElapsed
    ) public {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max) - 1);
        timeElapsed = uint32(bound(timeElapsed, deadline + 1, type(uint32).max));
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);
        address authorizer = vm.addr(privateKey);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuthorized,
            nonce: blue.nonce(authorizer),
            deadline: deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(blue.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.warp(block.timestamp + timeElapsed);

        vm.expectRevert(bytes(Errors.SIGNATURE_EXPIRED));
        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );
    }

    function testSetAuthorizationWithSignatureInvalidSignature(
        uint32 deadline,
        address authorized,
        uint256 privateKey,
        bool isAuthorized
    ) public {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);
        address authorizer = vm.addr(privateKey);
        vm.assume(authorizer != address(this));

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuthorized,
            nonce: blue.nonce(authorizer),
            deadline: deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(blue.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(bytes(Errors.INVALID_SIGNATURE));
        blue.setAuthorization(
            address(this), authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );
    }

    function testSetAuthorizationWithSignature(
        uint32 deadline,
        address authorized,
        uint256 privateKey,
        bool isAuthorized
    ) public {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);
        address authorizer = vm.addr(privateKey);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuthorized,
            nonce: blue.nonce(authorizer),
            deadline: deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(blue.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectEmit(true, true, true, true, address(blue));
        emit Events.SetAuthorization(
            address(this), authorization.authorizer, authorization.authorized, authorization.isAuthorized
        );
        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );

        assertEq(blue.isAuthorized(authorizer, authorized), isAuthorized);
        assertEq(blue.nonce(authorizer), 1);
    }

    function testSetAuthorizationWithSignatureInvalidNonce(
        uint32 deadline,
        address authorized,
        uint256 privateKey,
        bool isAuthorized,
        uint256 nonce
    ) public {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);
        address authorizer = vm.addr(privateKey);
        vm.assume(nonce != blue.nonce(authorizer));

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuthorized,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(blue.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(bytes(Errors.INVALID_SIGNATURE));
        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );
    }

    function testSetAuthorizationWithSignatureReplay(
        uint32 deadline,
        address authorized,
        uint256 privateKey,
        bool isAuthorized
    ) public {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);
        address authorizer = vm.addr(privateKey);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuthorized,
            nonce: blue.nonce(authorizer),
            deadline: deadline
        });

        bytes32 digest = SigUtils.getTypedDataHash(blue.DOMAIN_SEPARATOR(), authorization);

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );

        vm.expectRevert(bytes(Errors.INVALID_SIGNATURE));
        blue.setAuthorization(
            authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.deadline, sig
        );
    }
}
