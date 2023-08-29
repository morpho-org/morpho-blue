// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract OnlyOwnerIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;

    function testDeployWithAddressZero() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        new Morpho(address(0));
    }

    function testSetOwnerWhenNotOwner(address addressFuzz) public {
        vm.assume(addressFuzz != OWNER);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.setOwner(addressFuzz);
    }

    function testSetOwnerAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.ALREADY_SET));
        morpho.setOwner(OWNER);
    }

    function testSetOwner(address newOwner) public {
        vm.assume(newOwner != OWNER);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.SetOwner(newOwner);
        morpho.setOwner(newOwner);

        assertEq(morpho.owner(), newOwner, "owner is not set");
    }

    function testEnableIrmWhenNotOwner(address addressFuzz, address irmFuzz) public {
        vm.assume(addressFuzz != OWNER);
        vm.assume(irmFuzz != address(irm));

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.enableIrm(irmFuzz);
    }

    function testEnableIrmAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.ALREADY_SET));
        morpho.enableIrm(address(irm));
    }

    function testEnableIrm(address irmFuzz) public {
        vm.assume(irmFuzz != address(irm));

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.EnableIrm(irmFuzz);
        morpho.enableIrm(irmFuzz);

        assertTrue(morpho.isIrmEnabled(irmFuzz), "IRM is not enabled");
    }

    function testEnableLltvWhenNotOwner(address addressFuzz, uint256 lltvFuzz) public {
        vm.assume(addressFuzz != OWNER);
        vm.assume(lltvFuzz != LLTV);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.enableLltv(lltvFuzz);
    }

    function testEnableLltvAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.ALREADY_SET));
        morpho.enableLltv(LLTV);
    }

    function testEnableTooHighLltv(uint256 lltvFuzz) public {
        lltvFuzz = _boundInvalidLltv(lltvFuzz);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MAX_LLTV_EXCEEDED));
        morpho.enableLltv(lltvFuzz);
    }

    function testEnableLltv(uint256 lltvFuzz) public {
        lltvFuzz = _boundValidLltv(lltvFuzz);
        vm.assume(lltvFuzz != LLTV);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.EnableLltv(lltvFuzz);
        morpho.enableLltv(lltvFuzz);

        assertTrue(morpho.isLltvEnabled(lltvFuzz), "LLTV is not enabled");
    }

    function testSetFeeWhenNotOwner(address addressFuzz, uint256 feeFuzz) public {
        vm.assume(addressFuzz != OWNER);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.setFee(marketParams, feeFuzz);
    }

    function testSetFeeWhenMarketNotCreated(MarketParams memory marketParamsFuzz, uint256 feeFuzz) public {
        vm.assume(neq(marketParamsFuzz, marketParams));

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
        morpho.setFee(marketParamsFuzz, feeFuzz);
    }

    function testSetTooHighFee(uint256 feeFuzz) public {
        feeFuzz = bound(feeFuzz, MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(ErrorsLib.MAX_FEE_EXCEEDED));
        morpho.setFee(marketParams, feeFuzz);
    }

    function testSetFee(uint256 feeFuzz) public {
        feeFuzz = bound(feeFuzz, 1, MAX_FEE);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.SetFee(id, feeFuzz);
        morpho.setFee(marketParams, feeFuzz);

        assertEq(morpho.fee(id), feeFuzz);
    }

    function testSetFeeRecipientWhenNotOwner(address addressFuzz) public {
        vm.assume(addressFuzz != OWNER);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(ErrorsLib.NOT_OWNER));
        morpho.setFeeRecipient(addressFuzz);
    }

    function testSetFeeRecipient(address newFeeRecipient) public {
        vm.assume(newFeeRecipient != morpho.feeRecipient());

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(morpho));
        emit EventsLib.SetFeeRecipient(newFeeRecipient);
        morpho.setFeeRecipient(newFeeRecipient);

        assertEq(morpho.feeRecipient(), newFeeRecipient);
    }
}
