// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract InvariantTest is BaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    bytes4[] internal selectors;

    function setUp() public virtual override {
        super.setUp();

        _targetSenders();

        _supplyCollateralMax(targetSenders(), marketParams);

        _weightSelector(this.warp.selector, 20);

        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function _targetSenders() internal virtual {
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

    function _supplyCollateralMax(address[] memory users, MarketParams memory _marketParams) internal {
        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            collateralToken.setBalance(user, 1e30);

            vm.prank(user);
            morpho.supplyCollateral(_marketParams, 1e30, user, hex"");
        }
    }

    function warp(uint256 elapsed) external {
        elapsed = bound(elapsed, 12, 7 days);

        vm.roll(block.number + elapsed / 12);
        vm.warp(block.timestamp + elapsed);
    }

    function _randomSupplier(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address)
    {
        Id _id = _marketParams.id();
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (morpho.supplyShares(_id, user) != 0) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(users, seed);
    }

    function _randomBorrower(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address)
    {
        Id _id = _marketParams.id();
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (morpho.borrowShares(_id, user) != 0) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(users, seed);
    }

    function _randomHealthyCollateralSupplier(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address)
    {
        Id _id = _marketParams.id();
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (morpho.collateral(_id, user) != 0 && _isHealthy(_marketParams, user)) {
                candidates[i] = user;
            }
        }

        return _randomNonZero(users, seed);
    }

    function _randomUnhealthyBorrower(address[] memory users, MarketParams memory _marketParams, uint256 seed)
        internal
        view
        returns (address randomSenderToLiquidate)
    {
        address[] memory candidates = new address[](users.length);

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];

            if (!_isHealthy(_marketParams, user)) {
                candidates[i] = user;
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
}
