// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IOracle {
    function collateralPrice() external view returns (uint256 collateralPrice);

    function borrowPrice() external view returns (uint256 borrowPrice);
}
