// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ErrorsLib} from "../libraries/ErrorsLib.sol";

import {IERC20} from "../interfaces/IERC20.sol";

interface ERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title SafeTransferLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to manage tokens not fully ERC20 compliant:
///         not returning a boolean for `transfer` and `transferFrom` functions.
library SafeTransferLib {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory returndata) = address(token).call(abi.encodeCall(ERC20.transfer, (to, value)));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), ErrorsLib.TRANSFER_FAILED);
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(ERC20.transferFrom, (from, to, value)));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), ErrorsLib.TRANSFER_FROM_FAILED);
    }
}
