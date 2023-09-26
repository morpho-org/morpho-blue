// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IAuthority {
    function isAuthorized(address sender) external view returns (bool);
}
