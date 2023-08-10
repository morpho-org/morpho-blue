// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BaseTest.sol";

contract InvariantBaseTest is BaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

    bytes4[] internal selectors;

    address[] internal addressArray;

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

    function _randomSenderToWithdrawOnBehalf(address[] memory addresses, address seed, address sender)
        internal
        returns (address randomSenderToWithdrawOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (blue.supplyShares(id, addresses[i]) != 0) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToWithdrawOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        vm.prank(randomSenderToWithdrawOnBehalf);
        blue.setAuthorization(sender, true);

        delete addressArray;
    }

    function _randomSenderToBorrowOnBehalf(address[] memory addresses, address seed, address sender)
        internal
        returns (address randomSenderToBorrowOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (blue.collateral(id, addresses[i]) != 0 && isHealthy(market, id, addresses[i])) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToBorrowOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        vm.prank(randomSenderToBorrowOnBehalf);
        blue.setAuthorization(sender, true);

        delete addressArray; 
    }

    function _randomSenderToRepayOnBehalf(address[] memory addresses, address seed, address sender)
        internal
        returns (address randomSenderToRepayOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (blue.borrowShares(id, addresses[i]) != 0) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToRepayOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        delete addressArray;
    }

    function _randomSenderToWithdrawCollateralOnBehalf(address[] memory addresses, address seed, address sender)
        internal
        returns (address randomSenderToWithdrawCollateralOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (blue.collateral(id, addresses[i]) != 0 && isHealthy(market, id, addresses[i])) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToWithdrawCollateralOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        vm.prank(randomSenderToWithdrawCollateralOnBehalf);
        blue.setAuthorization(sender, true);

        delete addressArray; 
    }

    function _randomSenderToLiquidate(address[] memory addresses, address seed)
        internal
        returns (address randomSenderToLiquidate)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (blue.borrowShares(id, addresses[i]) != 0 && !isHealthy(market, id, addresses[i])) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToLiquidate = addressArray[uint256(uint160(seed)) % addressArray.length];

        delete addressArray;
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

    function isHealthy(Market memory market, Id id, address user) public view returns (bool) {
        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        uint256 borrowValue = blue.borrowShares(id, user).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id))
            .mulWadUp(borrowablePrice);
        uint256 collateralValue = blue.collateral(id, user).mulWadDown(collateralPrice);

        return collateralValue.mulWadDown(market.lltv) >= borrowValue;
    }
}
