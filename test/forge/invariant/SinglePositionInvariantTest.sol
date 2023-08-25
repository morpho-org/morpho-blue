// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SinglePositionInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    address user;

    function setUp() public virtual override {
        _weightSelector(this.supplyNoRevert.selector, 20);
        _weightSelector(this.withdrawNoRevert.selector, 15);
        _weightSelector(this.borrowNoRevert.selector, 15);
        _weightSelector(this.repayNoRevert.selector, 10);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralNoRevert.selector, 15);

        super.setUp();

        user = _addrFromHashedString("User");
        targetSender(user);

        collateralToken.setBalance(user, 1e30);
        vm.startPrank(user);
        borrowableToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams, 1e30, user, hex"");
        vm.stopPrank();

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);
    }

    function supplyNoRevert(uint256 assets) public {
        assets = _boundSupplyAssets(marketParams, user, assets);

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supply(marketParams, assets, 0, msg.sender, hex"");

        console2.log("supply", morpho.expectedSupplyBalance(marketParams, user));
    }

    function withdrawNoRevert(uint256 assets, address receiver) public {
        assets = _boundWithdrawAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, assets, 0, msg.sender, receiver);
    }

    function borrowNoRevert(uint256 assets, address receiver) public {
        assets = _boundBorrowAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.borrow(marketParams, assets, 0, msg.sender, receiver);
    }

    function repayNoRevert(uint256 assets) public {
        assets = _boundRepayAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.repay(marketParams, assets, 0, msg.sender, hex"");
    }

    function supplyCollateralNoRevert(uint256 assets) public {
        assets = _boundSupplyCollateralAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        collateralToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, assets, msg.sender, hex"");
    }

    function withdrawCollateralNoRevert(uint256 assets, address receiver) public {
        assets = _boundWithdrawCollateralAssets(marketParams, msg.sender, assets);
        if (assets == 0) return;

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, assets, msg.sender, receiver);
    }

    /* INVARIANTS */

    function invariantSupplyShares() public {
        assertEq(morpho.supplyShares(id, user), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(morpho.borrowShares(id, user), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        assertEq(morpho.expectedSupplyBalance(marketParams, user), morpho.totalSupplyAssets(id));
    }

    function invariantTotalBorrow() public {
        assertEq(morpho.expectedBorrowBalance(marketParams, user), morpho.totalBorrowAssets(id));
    }

    function invariantTotalSupplyGreaterThanTotalBorrow() public {
        assertGe(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id));
    }

    function invariantMorphoBalance() public {
        assertEq(
            borrowableToken.balanceOf(address(morpho)), morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id)
        );
    }

    // No price changes, and no new blocks so position has to remain healthy.
    function invariantHealthyPosition() public {
        assertTrue(_isHealthy(marketParams, user));
    }
}
