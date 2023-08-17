// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MorphoStorageLib} from "../../../src/libraries/periphery/MorphoStorageLib.sol";
import {SigUtils} from "test/forge/helpers/SigUtils.sol";

import "../BaseTest.sol";

contract MorphoStorageLibTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    function testStorage(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee) public {
        // Prepare storage layout with non empty values.

        amountSupplied = bound(amountSupplied, 2, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 1, amountSupplied);
        timeElapsed = uint32(bound(timeElapsed, 1, 1e8));
        fee = bound(fee, 1, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        morpho.setFeeRecipient(OWNER);
        morpho.setFee(market, fee);
        vm.stopPrank();

        borrowableToken.setBalance(address(this), amountSupplied);
        morpho.supply(market, amountSupplied, 0, address(this), hex"");

        uint256 collateralPrice = IOracle(market.oracle).price();
        collateralToken.setBalance(BORROWER, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice));

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(
            market, amountBorrowed.wDivUp(LLTV).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice), BORROWER, hex""
        );
        morpho.borrow(market, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 privateKey = 1;
        address authorizer = vm.addr(privateKey);
        Authorization memory authorization = Authorization({
            authorizer: authorizer,
            authorized: BORROWER,
            isAuthorized: true,
            nonce: 0,
            deadline: block.timestamp + type(uint32).max
        });

        Signature memory sig;
        bytes32 digest = SigUtils.getTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        morpho.setAuthorizationWithSig(authorization, sig);

        bytes32[] memory slots = new bytes32[](17);
        slots[0] = MorphoStorageLib.ownerSlot();
        slots[1] = MorphoStorageLib.feeRecipientSlot();
        slots[2] = MorphoStorageLib.userSlot(id, address(this));
        slots[3] = bytes32(uint256(MorphoStorageLib.userSlot(id, address(this))) + 1);
        slots[4] = MorphoStorageLib.totalSlot(id);
        slots[5] = bytes32(uint256(MorphoStorageLib.totalSlot(id)) + 1);
        slots[6] = MorphoStorageLib.lastUpdateSlot(id);
        slots[7] = MorphoStorageLib.feeSlot(id);
        slots[8] = MorphoStorageLib.isIrmEnabledSlot(address(irm));
        slots[9] = MorphoStorageLib.isLltvEnabledSlot(LLTV);
        slots[10] = MorphoStorageLib.isAuthorizedSlot(authorizer, BORROWER);
        slots[11] = MorphoStorageLib.nonceSlot(authorizer);
        slots[12] = MorphoStorageLib.idToBorrowableTokenSlot(id);
        slots[13] = MorphoStorageLib.idToCollateralTokenSlot(id);
        slots[14] = MorphoStorageLib.idToOracleSlot(id);
        slots[15] = MorphoStorageLib.idToIrmSlot(id);
        slots[16] = MorphoStorageLib.idToLltvSlot(id);

        bytes32[] memory values = morpho.extsload(slots);

        assertEq(abi.decode(abi.encode(values[0]), (address)), morpho.owner(), "a");
        assertEq(abi.decode(abi.encode(values[1]), (address)), morpho.feeRecipient(), "b");
        assertEq(uint256(values[2]), morpho.supplyShares(id, address(this)), "c");
        assertEq(
            uint256(values[3]), morpho.borrowShares(id, address(this)) << 128 | morpho.collateral(id, address(this))
        );
        // assertEq(uint256(values[4]), morpho.totalSupply(id) << 128 | morpho.totalSupplyShares(id));
        // assertEq(uint256(values[5]), morpho.totalBorrow(id) << 128 | morpho.totalBorrowShares(id));
        assertEq(uint256(values[6]), morpho.lastUpdate(id));
        assertEq(uint256(values[7]), morpho.fee(id));
        assertEq(abi.decode(abi.encode(values[8]), (bool)), morpho.isIrmEnabled(address(irm)));
        assertEq(abi.decode(abi.encode(values[9]), (bool)), morpho.isLltvEnabled(LLTV));
        assertEq(abi.decode(abi.encode(values[10]), (bool)), morpho.isAuthorized(authorizer, BORROWER));
        assertEq(uint256(values[11]), morpho.nonce(authorizer));

        (
            address expectedBorrowableToken,
            address expectedCollateralToken,
            address expectedOracle,
            address expectedIrm,
            uint256 expectedLltv
        ) = morpho.idToMarket(id);
        assertEq(abi.decode(abi.encode(values[12]), (address)), expectedBorrowableToken);
        assertEq(abi.decode(abi.encode(values[13]), (address)), expectedCollateralToken);
        assertEq(abi.decode(abi.encode(values[14]), (address)), expectedOracle);
        assertEq(abi.decode(abi.encode(values[15]), (address)), expectedIrm);
        assertEq(uint256(values[16]), expectedLltv);
    }
}
