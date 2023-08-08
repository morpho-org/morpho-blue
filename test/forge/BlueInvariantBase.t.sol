// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "test/forge/BlueBase.t.sol";

contract InvariantBaseTest is BlueBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    bytes4[] internal selectors;

    function setUp() public virtual override {
        super.setUp();

        targetContract(address(this));
    }

    function _targetDefaultSenders() internal {
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address1")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address2")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address3")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address4")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address5")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address6")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address7")))));
        targetSender(address(uint160(uint256(keccak256("Morpho Blue address8")))));
    }

    function _weightSelector(bytes4 selector, uint256 weight) internal {
        for (uint256 i; i < weight; ++i) {
            selectors.push(selector);
        }
    }

    function sumUsersSupplyShares(address[] memory addresses) internal view returns (uint256) {
        uint256 sum;
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.supplyShares(id, addresses[i]);
        }
        return sum;
    }

    function sumUsersBorrowShares(address[] memory addresses) internal view returns (uint256) {
        uint256 sum;
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.borrowShares(id, addresses[i]);
        }
        return sum;
    }

    function sumUsersSuppliedAmounts(address[] memory addresses) internal view returns (uint256) {
        uint256 sum;
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.supplyShares(id, addresses[i]).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        }
        return sum;
    }

    function sumUsersBorrowedAmounts(address[] memory addresses) internal view returns (uint256) {
        uint256 sum;
        for (uint256 i; i < addresses.length; ++i) {
            sum += blue.borrowShares(id, addresses[i]).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        }
        return sum;
    }
}
