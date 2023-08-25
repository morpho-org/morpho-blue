// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract InvariantTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    uint256 blockNumber;
    uint256 timestamp;

    bytes4[] internal selectors;

    function setUp() public virtual override {
        super.setUp();

        targetContract(address(this));

        blockNumber = block.number;
        timestamp = block.timestamp;
    }

    function _targetDefaultSenders() internal {
        _targetSender(_addrFromHashedString("Sender1"));
        _targetSender(_addrFromHashedString("Sender2"));
        _targetSender(_addrFromHashedString("Sender3"));
        _targetSender(_addrFromHashedString("Sender4"));
        _targetSender(_addrFromHashedString("Sender5"));
        _targetSender(_addrFromHashedString("Sender6"));
        _targetSender(_addrFromHashedString("Sender7"));
        _targetSender(_addrFromHashedString("Sender8"));
    }

    function _targetSender(address sender) internal {
        targetSender(sender);

        vm.startPrank(sender);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    function _weightSelector(bytes4 selector, uint256 weight) internal {
        for (uint256 i; i < weight; ++i) {
            selectors.push(selector);
        }
    }

    function _supplyHighAmountOfCollateralForAllSenders(address[] memory users, MarketParams memory marketParams)
        internal
    {
        for (uint256 i; i < users.length; ++i) {
            collateralToken.setBalance(users[i], 1e30);
            vm.prank(users[i]);
            morpho.supplyCollateral(marketParams, 1e30, users[i], hex"");
        }
    }

    /// @dev Permanently setting block number and timestamp with cheatcodes in this function doesn't work at the moment,
    ///      they get reset to the ones defined in the set up function after each function call.
    ///      The solution we choose is to save these in storage, and set them with roll and warp cheatcodes with the
    ///      setCorrectBlock function at the the beginning of each function.
    ///      The purpose of this function is to increment these variables to simulate a new block.
    function newBlock(uint256 elapsed) external {
        elapsed = bound(elapsed, 10, 7 days);

        blockNumber += 1;
        timestamp += elapsed;
    }

    modifier setCorrectBlock() {
        vm.roll(blockNumber);
        vm.warp(timestamp);
        _;
    }

    function _randomSupplier(address[] memory users, uint256 seed) internal returns (address) {
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            if (morpho.supplyShares(id, users[i]) != 0) {
                candidates[i] = users[i];
            }
        }

        return _randomNonZero(users, seed);
    }

    function _randomBorrower(address[] memory users, uint256 seed) internal returns (address) {
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            if (morpho.borrowShares(id, users[i]) != 0) {
                candidates[i] = users[i];
            }
        }

        return _randomNonZero(users, seed);
    }

    function _randomHealthyCollateralSupplier(address[] memory users, uint256 seed) internal returns (address) {
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            if (morpho.collateral(id, users[i]) != 0 && isHealthy(id, users[i])) {
                candidates[i] = users[i];
            }
        }

        return _randomNonZero(users, seed);
    }

    function _randomUnhealthyBorrower(address[] memory users, uint256 seed)
        internal
        returns (address randomSenderToLiquidate)
    {
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            if (!isHealthy(id, users[i])) {
                candidates[i] = users[i];
            }
        }

        return _randomNonZero(users, seed);
    }

    function sumSupplyShares(address[] memory users) internal view returns (uint256 sum) {
        for (uint256 i; i < users.length; ++i) {
            sum += morpho.supplyShares(id, users[i]);
        }

        sum += morpho.supplyShares(id, morpho.feeRecipient());
    }

    function sumBorrowShares(address[] memory users) internal view returns (uint256 sum) {
        for (uint256 i; i < users.length; ++i) {
            sum += morpho.borrowShares(id, users[i]);
        }
    }

    function sumSupplyAssets(address[] memory users) internal view returns (uint256 sum) {
        for (uint256 i; i < users.length; ++i) {
            sum += morpho.expectedSupplyBalance(marketParams, users[i]);
            console2.log(sum);
        }

        sum += morpho.expectedSupplyBalance(marketParams, morpho.feeRecipient());
    }

    function sumBorrowAssets(address[] memory users) internal view returns (uint256 sum) {
        for (uint256 i; i < users.length; ++i) {
            sum += morpho.expectedBorrowBalance(marketParams, users[i]);
            console2.log(sum);
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
}
