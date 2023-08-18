// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MorphoStorageLib} from "../../../src/libraries/periphery/MorphoStorageLib.sol";
import {SigUtils} from "test/forge/helpers/SigUtils.sol";

import "../BaseTest.sol";

contract MorphoStorageLibTest is BaseTest {
    using MathLib for uint256;
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

        uint256[] memory slots = new uint256[](20);
        slots[0] = MorphoStorageLib.ownerSlot();
        slots[1] = MorphoStorageLib.feeRecipientSlot();
        slots[2] = MorphoStorageLib.supplySharesSlot(id, address(this));
        slots[3] = MorphoStorageLib.borrowSharesSlot(id, address(this));
        slots[4] = MorphoStorageLib.collateralSlot(id, address(this));
        slots[5] = MorphoStorageLib.totalSupplySlot(id);
        slots[6] = MorphoStorageLib.totalSupplySharesSlot(id);
        slots[7] = MorphoStorageLib.totalBorrowSlot(id);
        slots[8] = MorphoStorageLib.totalBorrowSharesSlot(id);
        slots[9] = MorphoStorageLib.lastUpdateSlot(id);
        slots[10] = MorphoStorageLib.feeSlot(id);
        slots[11] = MorphoStorageLib.isIrmEnabledSlot(address(irm));
        slots[12] = MorphoStorageLib.isLltvEnabledSlot(LLTV);
        slots[13] = MorphoStorageLib.isAuthorizedSlot(authorizer, BORROWER);
        slots[14] = MorphoStorageLib.nonceSlot(authorizer);
        slots[15] = MorphoStorageLib.idToBorrowableTokenSlot(id);
        slots[16] = MorphoStorageLib.idToCollateralTokenSlot(id);
        slots[17] = MorphoStorageLib.idToOracleSlot(id);
        slots[18] = MorphoStorageLib.idToIrmSlot(id);
        slots[19] = MorphoStorageLib.idToLltvSlot(id);

        bytes32[] memory values = morpho.sloads(slots);

        assertEq(uint256(values[0]), uint256(uint160(morpho.owner())));
        assertEq(uint256(values[1]), uint256(uint160(morpho.feeRecipient())));
        assertEq(uint256(values[2]), morpho.supplyShares(id, address(this)));
        assertEq(uint256(values[3]), morpho.borrowShares(id, address(this)));
        assertEq(uint256(values[4]), morpho.collateral(id, address(this)));
        assertEq(uint256(values[5]), morpho.totalSupply(id));
        assertEq(uint256(values[6]), morpho.totalSupplyShares(id));
        assertEq(uint256(values[7]), morpho.totalBorrow(id));
        assertEq(uint256(values[8]), morpho.totalBorrowShares(id));
        assertEq(uint256(values[9]), morpho.lastUpdate(id));
        assertEq(uint256(values[10]), morpho.fee(id));
        assertEq(uint256(values[11]), morpho.isIrmEnabled(address(irm)) ? 1 : 0);
        assertEq(uint256(values[12]), morpho.isLltvEnabled(LLTV) ? 1 : 0);
        assertEq(uint256(values[13]), morpho.isAuthorized(authorizer, BORROWER) ? 1 : 0);
        assertEq(uint256(values[14]), morpho.nonce(authorizer));

        (
            address expectedBorrowableToken,
            address expectedCollateralToken,
            address expectedOracle,
            address expectedIrm,
            uint256 expectedLltv
        ) = morpho.idToMarket(id);
        assertEq(uint256(values[15]), uint256(uint160(expectedBorrowableToken)));
        assertEq(uint256(values[16]), uint256(uint160(expectedCollateralToken)));
        assertEq(uint256(values[17]), uint256(uint160(expectedOracle)));
        assertEq(uint256(values[18]), uint256(uint160(expectedIrm)));
        assertEq(uint256(values[19]), expectedLltv);
    }
}
