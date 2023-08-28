// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "test/forge/BaseTest.sol";

contract InvariantTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    uint256 blockNumber;
    uint256 timestamp;

    bytes4[] internal selectors;

    address[] internal addressArray;

    function setUp() public virtual override {
        super.setUp();

        targetContract(address(this));

        blockNumber = block.number;
        timestamp = block.timestamp;
    }

    function _targetDefaultSenders() internal {
        targetSender(_addrFromHashedString("Morpho address1"));
        targetSender(_addrFromHashedString("Morpho address2"));
        targetSender(_addrFromHashedString("Morpho address3"));
        targetSender(_addrFromHashedString("Morpho address4"));
        targetSender(_addrFromHashedString("Morpho address5"));
        targetSender(_addrFromHashedString("Morpho address6"));
        targetSender(_addrFromHashedString("Morpho address7"));
        targetSender(_addrFromHashedString("Morpho address8"));
    }

    function _weightSelector(bytes4 selector, uint256 weight) internal {
        for (uint256 i; i < weight; ++i) {
            selectors.push(selector);
        }
    }

    function _approveSendersTransfers(address[] memory senders) internal {
        for (uint256 i; i < senders.length; ++i) {
            vm.startPrank(senders[i]);
            borrowableToken.approve(address(morpho), type(uint256).max);
            collateralToken.approve(address(morpho), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _supplyHighAmountOfCollateralForAllSenders(address[] memory senders, MarketParams memory marketParams)
        internal
    {
        for (uint256 i; i < senders.length; ++i) {
            collateralToken.setBalance(senders[i], 1e30);
            vm.prank(senders[i]);
            morpho.supplyCollateral(marketParams, 1e30, senders[i], hex"");
        }
    }

    /// @dev Permanently setting block number and timestamp with cheatcodes in this function doesn't work at the moment,
    ///      they get reset to the ones defined in the set up function after each function call.
    ///      The solution we choose is to save these in storage, and set them with roll and warp cheatcodes with the
    ///      setCorrectBlock function at the the beginning of each function.
    ///      The purpose of this function is to increment these variables to simulate a new block.
    function newBlock(uint256 elapsed) public {
        elapsed = bound(elapsed, 10, 1 days);

        blockNumber += 1;
        timestamp += elapsed;
    }

    modifier setCorrectBlock() {
        vm.roll(blockNumber);
        vm.warp(timestamp);
        _;
    }

    function _randomSenderToWithdrawOnBehalf(address[] memory addresses, address seed, address sender)
        internal
        returns (address randomSenderToWithdrawOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (morpho.supplyShares(id, addresses[i]) != 0) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToWithdrawOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        vm.prank(randomSenderToWithdrawOnBehalf);
        morpho.setAuthorization(sender, true);

        delete addressArray;
    }

    function _randomSenderToBorrowOnBehalf(address[] memory addresses, address seed, address sender)
        internal
        returns (address randomSenderToBorrowOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (morpho.collateral(id, addresses[i]) != 0 && isHealthy(id, addresses[i])) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToBorrowOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        vm.prank(randomSenderToBorrowOnBehalf);
        morpho.setAuthorization(sender, true);

        delete addressArray;
    }

    function _randomSenderToRepayOnBehalf(address[] memory addresses, address seed)
        internal
        returns (address randomSenderToRepayOnBehalf)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (morpho.borrowShares(id, addresses[i]) != 0) {
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
            if (morpho.collateral(id, addresses[i]) != 0 && isHealthy(id, addresses[i])) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToWithdrawCollateralOnBehalf = addressArray[uint256(uint160(seed)) % addressArray.length];

        vm.prank(randomSenderToWithdrawCollateralOnBehalf);
        morpho.setAuthorization(sender, true);

        delete addressArray;
    }

    function _randomSenderToLiquidate(address[] memory addresses, address seed)
        internal
        returns (address randomSenderToLiquidate)
    {
        for (uint256 i; i < addresses.length; ++i) {
            if (!isHealthy(id, addresses[i])) {
                addressArray.push(addresses[i]);
            }
        }
        if (addressArray.length == 0) return address(0);

        randomSenderToLiquidate = addressArray[uint256(uint160(seed)) % addressArray.length];

        delete addressArray;
    }

    function sumUsersSupplyShares(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += morpho.supplyShares(id, addresses[i]);
        }
        sum += morpho.supplyShares(id, morpho.feeRecipient());
    }

    function sumUsersBorrowShares(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += morpho.borrowShares(id, addresses[i]);
        }
    }

    function sumUsersSuppliedAmounts(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += morpho.supplyShares(id, addresses[i]).toAssetsDown(
                morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id)
            );
        }
        sum += morpho.supplyShares(id, morpho.feeRecipient()).toAssetsDown(
            morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id)
        );
    }

    function sumUsersBorrowedAmounts(address[] memory addresses) internal view returns (uint256 sum) {
        for (uint256 i; i < addresses.length; ++i) {
            sum += morpho.borrowShares(id, addresses[i]).toAssetsUp(
                morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id)
            );
        }
    }

    function isHealthy(Id id, address user) public view returns (bool) {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 borrowed =
            morpho.borrowShares(id, user).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 maxBorrow =
            morpho.collateral(id, user).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        return maxBorrow >= borrowed;
    }

    function _liquidationIncentiveFactor(uint256 lltv) internal pure returns (uint256) {
        return
            UtilsLib.min(MAX_LIQUIDATION_INCENTIVE_FACTOR, WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - lltv)));
    }
}
