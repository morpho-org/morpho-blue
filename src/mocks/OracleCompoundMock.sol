// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

contract OracleCompoundMock {
    uint256 internal price;

    function getUnderlyingPrice() external view returns (uint256) {
        return price;
    }

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}
