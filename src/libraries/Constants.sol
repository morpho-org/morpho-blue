// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

/// @dev The number of tranches to define in a single market. Must be less than or equal to 256.
uint256 constant NB_TRANCHES = 64;

/// @dev The number of shares attributed to the first depositor of a tranche. Avoids inflation attack.
uint256 constant INITIAL_SHARES = WadRayMath.WAD;

uint256 constant LIQUIDATION_HEALTH_FACTOR = WadRayMath.WAD;
uint256 constant LIQUIDATION_BONUS_FACTOR = WadRayMath.HALF_WAD;

/// @dev The name used for EIP-712 signature.
string constant EIP712_NAME = "Morpho Blue";

/// @dev The typehash for approveManagerWithSig approval used for the EIP-712 signature.
bytes32 constant EIP712_APPROVAL_TYPEHASH =
    keccak256("Approval(address delegator,address manager,uint256 newAllowance,uint256 nonce,uint256 deadline)");

/// @dev The expected success hash returned by the FlashLiquidator.
bytes32 constant FLASH_LIQUIDATOR_SUCCESS_HASH = keccak256("ERC3156xFlashLiquidator.onLiquidation");
