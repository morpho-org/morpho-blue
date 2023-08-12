// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";

library SafeTransferLib {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory returndata) = address(token).call(abi.encodeCall(token.transfer, (to, value)));
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "TRANSFER_FAILED");
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, value)));
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "TRANSFER_FROM_FAILED");
    }
}
