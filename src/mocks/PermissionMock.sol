// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermission} from "../interfaces/IPermission.sol";

contract PermissionMock is IPermission {
    function isPermissioned(address) external pure returns (bool) {
        return true;
    }
}
