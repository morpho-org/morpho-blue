// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id} from "../MarketLib.sol";

/// @title MorphoStorageLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Helper library exposing getters to access Morpho storage variables' slot.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
library MorphoStorageLib {
    /* SLOTS */

    uint256 internal constant OWNER_SLOT = 0;
    uint256 internal constant FEE_RECIPIENT_SLOT = 1;
    uint256 internal constant USER_SLOT = 2;
    uint256 internal constant TOTAL_SUPPLY_SLOT = 3;
    uint256 internal constant TOTAL_SUPPLY_SHARES_SLOT = 4;
    uint256 internal constant TOTAL_BORROW_SLOT = 5;
    uint256 internal constant TOTAL_BORROW_SHARES_SLOT = 6;
    uint256 internal constant LAST_UPDATE_SLOT = 7;
    uint256 internal constant FEE_SLOT = 8;
    uint256 internal constant IS_IRM_ENABLED_SLOT = 9;
    uint256 internal constant IS_LLTV_ENABLED_SLOT = 10;
    uint256 internal constant IS_AUTHORIZED_SLOT = 11;
    uint256 internal constant NONCE_SLOT = 12;
    uint256 internal constant ID_TO_MARKET_SLOT = 13;

    /* SLOT OFFSETS */

    uint256 internal constant BORROWABLE_TOKEN_OFFSET = 0;
    uint256 internal constant COLLATERAL_TOKEN_OFFSET = 1;
    uint256 internal constant ORACLE_OFFSET = 2;
    uint256 internal constant IRM_OFFSET = 3;
    uint256 internal constant LLTV_OFFSET = 4;

    /* GETTERS */

    function ownerSlot() internal pure returns (bytes32) {
        return bytes32(OWNER_SLOT);
    }

    function feeRecipientSlot() internal pure returns (bytes32) {
        return bytes32(FEE_RECIPIENT_SLOT);
    }

    function userSlot(Id id, address user) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, keccak256(abi.encode(id, USER_SLOT))));
    }

    function totalSupplySlot(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_SUPPLY_SLOT));
    }

    function totalSupplySharesSlot(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_SUPPLY_SHARES_SLOT));
    }

    function totalBorrowSlot(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_BORROW_SLOT));
    }

    function totalBorrowSharesSlot(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_BORROW_SHARES_SLOT));
    }

    function lastUpdateSlot(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, LAST_UPDATE_SLOT));
    }

    function feeSlot(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, FEE_SLOT));
    }

    function isIrmEnabledSlot(address irm) internal pure returns (bytes32) {
        return keccak256(abi.encode(irm, IS_IRM_ENABLED_SLOT));
    }

    function isLltvEnabledSlot(uint256 lltv) internal pure returns (bytes32) {
        return keccak256(abi.encode(lltv, IS_LLTV_ENABLED_SLOT));
    }

    function isAuthorizedSlot(address authorizer, address authorizee) internal pure returns (bytes32) {
        return keccak256(abi.encode(authorizee, keccak256(abi.encode(authorizer, IS_AUTHORIZED_SLOT))));
    }

    function nonceSlot(address authorizer) internal pure returns (bytes32) {
        return keccak256(abi.encode(authorizer, NONCE_SLOT));
    }

    function idToBorrowableTokenSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_SLOT))) + BORROWABLE_TOKEN_OFFSET);
    }

    function idToCollateralTokenSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_SLOT))) + COLLATERAL_TOKEN_OFFSET);
    }

    function idToOracleSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_SLOT))) + ORACLE_OFFSET);
    }

    function idToIrmSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_SLOT))) + IRM_OFFSET);
    }

    function idToLltvSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_SLOT))) + LLTV_OFFSET);
    }
}
