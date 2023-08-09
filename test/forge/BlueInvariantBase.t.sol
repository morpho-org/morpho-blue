// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BaseTest.sol";

contract InvariantBaseTest is BaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    bytes4[] internal selectors;

    function setUp() public virtual override {
        super.setUp();

        targetContract(address(this));
    }

    function _targetDefaultSenders() internal {
        targetSender(_addrFromHashedString("Morpho Blue address1"));
        targetSender(_addrFromHashedString("Morpho Blue address2"));
        targetSender(_addrFromHashedString("Morpho Blue address3"));
        targetSender(_addrFromHashedString("Morpho Blue address4"));
        targetSender(_addrFromHashedString("Morpho Blue address5"));
        targetSender(_addrFromHashedString("Morpho Blue address6"));
        targetSender(_addrFromHashedString("Morpho Blue address7"));
        targetSender(_addrFromHashedString("Morpho Blue address8"));
    }

    function _weightSelector(bytes4 selector, uint256 weight) internal {
        for (uint256 i; i < weight; ++i) {
            selectors.push(selector);
        }
    }

    function sumUsersSupplyShares(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.supplyShares(id, addresses[i]);
        }
    }

    function sumUsersBorrowShares(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.borrowShares(id, addresses[i]);
        }
    }

    function sumUsersSuppliedAmounts(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.supplyShares(id, addresses[i]).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        }
    }

    function sumUsersBorrowedAmounts(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.borrowShares(id, addresses[i]).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        }
    }
}
