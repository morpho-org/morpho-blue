// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.12;

import {ErrorsLib} from "../libraries/ErrorsLib.sol";

import {IERC20} from "../interfaces/IERC20.sol";

interface IERC20Internal {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title SafeTransferLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to manage tokens not fully ERC20 compliant:
///         not returning a boolean for `transfer` and `transferFrom` functions.
/// @dev It is the responsibility of the market creator to make sure that the address of the token has non-zero code.
library SafeTransferLib {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(IERC20Internal.transfer, (to, value)));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), ErrorsLib.TRANSFER_FAILED);
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(IERC20Internal.transferFrom, (from, to, value)));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), ErrorsLib.TRANSFER_FROM_FAILED);
    }
}
