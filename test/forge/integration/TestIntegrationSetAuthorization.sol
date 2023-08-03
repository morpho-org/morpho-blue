// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SigUtils} from "../helpers/SigUtils.sol";

import "test/forge/BlueBase.t.sol";

contract IntegrationAuthorization is BlueBaseTest {
    function testSetAuthorization(address addressFuzz) public {
        vm.assume(addressFuzz != address(this));

        blue.setAuthorization(addressFuzz, true);

        assertTrue(blue.isAuthorized(address(this), addressFuzz));

        blue.setAuthorization(addressFuzz, false);

        assertFalse(blue.isAuthorized(address(this), addressFuzz));
    }

    //set authorization with signature

    function testSetAuthorizationWithSignatureDeadlineOutdated(
        uint32 deadline,
        address authorized,
        uint256 privateKey,
        bool isAuthorized,
        uint256 timeElapsed
    ) public {
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max) - 1);
        timeElapsed = uint32(bound(timeElapsed, deadline + 1, type(uint32).max));
        privateKey = bound(privateKey, 1, type(uint32).max); // "Private key must be less than the secp256k1 curve order (115792089237316195423570985008687907852837564279074904382605163141518161494337)."
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
        privateKey = bound(privateKey, 1, type(uint32).max); // "Private key must be less than the secp256k1 curve order (115792089237316195423570985008687907852837564279074904382605163141518161494337)."
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
        privateKey = bound(privateKey, 1, type(uint32).max); // "Private key must be less than the secp256k1 curve order (115792089237316195423570985008687907852837564279074904382605163141518161494337)."
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

        assertEq(blue.isAuthorized(authorizer, authorized), isAuthorized);
        assertEq(blue.nonce(authorizer), 1);
    }
}
