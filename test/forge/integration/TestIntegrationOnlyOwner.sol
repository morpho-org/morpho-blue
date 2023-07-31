// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract IntegrationOnlyOwnerTest is BlueBaseTest {
    using MarketLib for Market;
    using FixedPointMathLib for uint256;

    function testTransferOwnershipWhenNotOwner(address addressFuzz) public {
        vm.assume(addressFuzz != OWNER);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.transferOwnership(addressFuzz);
    }

    function testTransferOwnership(address newOwner) public {
        vm.assume(newOwner != OWNER);

        vm.prank(OWNER);
        blue.transferOwnership(newOwner);

        assertEq(blue.owner(), newOwner, 'owner');
    }

    function testEnableIrmWhenNotOwner(address addressFuzz, Irm irmFuzz) public {
        vm.assume(addressFuzz != OWNER);
        vm.assume(irmFuzz != irm);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.enableIrm(irmFuzz);
    }

    function testEnableIrm(Irm irmFuzz) public {
        vm.assume(irmFuzz != irm);

        vm.prank(OWNER);
        blue.enableIrm(irmFuzz);

        assertTrue(blue.isIrmEnabled(irmFuzz), 'Irm is enabled');
    }

    function testEnableLLTVWhenNotOwner(address addressFuzz, uint256 LLTVFuzz) public {
        vm.assume(addressFuzz != OWNER);
        vm.assume(LLTVFuzz != LLTV);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.enableLltv(LLTVFuzz);
    }

    function testEnableTooHighLLTV(uint256 LLTVFuzz) public {
        vm.assume(LLTVFuzz != LLTV);
        vm.assume(LLTVFuzz >= FixedPointMathLib.WAD);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.LLTV_TOO_HIGH));
        blue.enableLltv(LLTVFuzz);
    }

    function testEnableLLTV(uint256 LLTVFuzz) public {
        vm.assume(LLTVFuzz != LLTV);
        vm.assume(LLTVFuzz < FixedPointMathLib.WAD);

        vm.prank(OWNER);
        blue.enableLltv(LLTVFuzz);

        assertTrue(blue.isLltvEnabled(LLTVFuzz), 'Lltv is enabled');
    }

    function testSetFeeWhenNotOwner(address addressFuzz, uint256 feeFuzz) public {
        vm.assume(addressFuzz != OWNER);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.setFee(market, feeFuzz);
    }

    function testSetFeeWhenMarketNotCreated(Market memory marketFuzz, uint256 feeFuzz) public {
        vm.assume(neq(marketFuzz, market));

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.MARKET_NOT_CREATED));
        blue.setFee(marketFuzz, feeFuzz);
    }

    function testSetTooHighFee(uint256 feeFuzz) public {
        feeFuzz = bound(feeFuzz, MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(bytes(Errors.MAX_FEE_EXCEEDED));
        blue.setFee(market, feeFuzz);
    }

    function testSetFee(uint256 feeFuzz) public {
        feeFuzz = bound(feeFuzz, 0, MAX_FEE);

        vm.prank(OWNER);
        blue.setFee(market, feeFuzz);

        assertEq(blue.fee(id), feeFuzz);
    }

    function testSetFeeRecipientWhenNotOwner(address addressFuzz) public {
        vm.assume(addressFuzz != OWNER);

        vm.prank(addressFuzz);
        vm.expectRevert(bytes(Errors.NOT_OWNER));
        blue.setFeeRecipient(addressFuzz);
    }

    function testSetFeeRecipient(address newFeeRecipient) public {
        vm.assume(newFeeRecipient != OWNER);

        vm.prank(OWNER);
        blue.setFeeRecipient(newFeeRecipient);

        assertEq(blue.feeRecipient(), newFeeRecipient);
    }
}