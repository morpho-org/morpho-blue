// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Id} from "../MarketLib.sol";

/// @title MorphoStorageLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Helper library exposing getters to access Morpho storage variables' slot.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
library MorphoStorageLib {
    uint256 internal constant OWNER_SLOT = 0;
    uint256 internal constant FEE_RECIPIENT_SLOT = 1;
    uint256 internal constant SUPPLY_SHARES_SLOT = 2;
    uint256 internal constant BORROW_SHARES_SLOT = 3;
    uint256 internal constant COLLATERAL_SLOT = 4;
    uint256 internal constant TOTAL_SUPPLY_SLOT = 5;
    uint256 internal constant TOTAL_SUPPLY_SHARES_SLOT = 6;
    uint256 internal constant TOTAL_BORROW_SLOT = 7;
    uint256 internal constant TOTAL_BORROW_SHARES_SLOT = 8;
    uint256 internal constant LAST_UPDATE_SLOT = 9;
    uint256 internal constant FEE_SLOT = 10;
    uint256 internal constant IS_IRM_ENABLED_SLOT = 11;
    uint256 internal constant IS_LLTV_ENABLED_SLOT = 12;
    uint256 internal constant IS_AUTHORIZED_SLOT = 13;

    function owner() internal pure returns (bytes32) {
        return bytes32(OWNER_SLOT);
    }

    function feeRecipient() internal pure returns (bytes32) {
        return bytes32(FEE_RECIPIENT_SLOT);
    }

    function supplyShares(Id id, address user) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, keccak256(abi.encode(id, SUPPLY_SHARES_SLOT))));
    }

    function borrowShares(Id id, address user) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, keccak256(abi.encode(id, BORROW_SHARES_SLOT))));
    }

    function collateral(Id id, address user) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, keccak256(abi.encode(id, COLLATERAL_SLOT))));
    }

    function totalSupply(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_SUPPLY_SLOT));
    }

    function totalSupplyShares(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_SUPPLY_SHARES_SLOT));
    }

    function totalBorrow(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_BORROW_SLOT));
    }

    function totalBorrowShares(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, TOTAL_BORROW_SHARES_SLOT));
    }

    function lastUpdate(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, LAST_UPDATE_SLOT));
    }

    function fee(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, FEE_SLOT));
    }

    function isIrmEnabled(address irm) internal pure returns (bytes32) {
        return keccak256(abi.encode(irm, IS_IRM_ENABLED_SLOT));
    }

    function isLltvEnabled(uint256 lltv) internal pure returns (bytes32) {
        return keccak256(abi.encode(lltv, IS_LLTV_ENABLED_SLOT));
    }

    function isAuthorized(address delegator, address manager) internal pure returns (bytes32) {
        return keccak256(abi.encode(manager, keccak256(abi.encode(delegator, IS_AUTHORIZED_SLOT))));
    }
}
