// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";

import {ErrorsLib} from "../libraries/ErrorsLib.sol";

interface IERC20Internal {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title SafeTransferLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to manage transfers of tokens, even if calls to the transfer or transferFrom functions are not
/// returning a boolean.
/// @dev It is the responsibility of the market creator to make sure that the address of the token has non-zero code.
library SafeTransferLib {
    /// @dev Warning: It does not revert on `token` with no code.
    function safeTransfer(IERC20 token, address to, uint256 value, bytes4 selector) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeWithSelector(IERC20Internal.transfer.selector, to, value, selector));
        require(success, ErrorsLib.TRANSFER_REVERTED);
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ErrorsLib.TRANSFER_RETURNED_FALSE);
    }

    /// @dev Warning: It does not revert on `token` with no code.
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value, bytes4 selector) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeWithSelector(IERC20Internal.transferFrom.selector, from, to, value, selector));
        require(success, ErrorsLib.TRANSFER_FROM_REVERTED);
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ErrorsLib.TRANSFER_FROM_RETURNED_FALSE);
    }
}
