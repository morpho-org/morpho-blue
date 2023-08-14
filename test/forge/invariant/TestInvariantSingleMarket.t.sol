// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantBase.sol";

contract SingleMarketInvariantTest is InvariantBaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());
        _supplyHighAmountOfCollateralForAllSenders(targetSenders(), market);

        // High price because of the 1e36 price scale
        oracle.setPrice(1e40);

        _weightSelector(this.supplyOnMorpho.selector, 20);
        _weightSelector(this.borrowOnMorpho.selector, 20);
        _weightSelector(this.repayOnMorpho.selector, 20);
        _weightSelector(this.withdrawOnMorpho.selector, 20);
        _weightSelector(this.supplyCollateralOnMorpho.selector, 20);
        _weightSelector(this.withdrawCollateralOnMorpho.selector, 20);
        _weightSelector(this.newBlock.selector, 5);
        _weightSelector(this.setMarketFee.selector, 2);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function newBlock(uint8 elapsed) public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);
    }

    function setMarketFee(uint256 newFee) public {
        newFee = bound(newFee, 0, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(market, newFee);
    }

    function supplyOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supply(market, amount, 0, msg.sender, hex"");
    }

    function withdrawOnMorpho(uint256 amount) public {
        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (morpho.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        morpho.accrueInterests(market);
        uint256 supplierBalance =
            morpho.supplyShares(id, msg.sender).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(market, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorpho(uint256 amount) public {
        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (availableLiquidity == 0) return;

        morpho.accrueInterests(market);
        amount = bound(amount, 1, availableLiquidity);

        vm.prank(msg.sender);
        morpho.borrow(market, amount, 0, msg.sender, msg.sender);
    }

    function repayOnMorpho(uint256 amount) public {
        if (morpho.borrowShares(id, msg.sender) == 0) return;

        morpho.accrueInterests(market);
        amount = bound(
            amount,
            1,
            morpho.borrowShares(id, msg.sender).toAssetsDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id))
        );

        borrowableToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.repay(market, amount, 0, msg.sender, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        collateralToken.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        morpho.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function invariantSupplyShares() public {
        assertEq(sumUsersSupplyShares(targetSenders()), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(sumUsersBorrowShares(targetSenders()), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        assertLe(sumUsersSuppliedAmounts(targetSenders()), morpho.totalSupply(id));
    }

    function invariantTotalBorrow() public {
        assertGe(sumUsersBorrowedAmounts(targetSenders()), morpho.totalBorrow(id));
    }

    function invariantTotalBorrowLessThanTotalSupply() public {
        assertGe(morpho.totalSupply(id), morpho.totalBorrow(id));
    }

    function invariantMorphoBalance() public {
        assertEq(morpho.totalSupply(id) - morpho.totalBorrow(id), borrowableToken.balanceOf(address(morpho)));
    }

    function invariantSupplySharesRatio() public {
        if (morpho.totalSupply(id) == 0) return;
        assertGe(morpho.totalSupplyShares(id) / morpho.totalSupply(id), SharesMathLib.VIRTUAL_SHARES);
    }

    function invariantBorrowSharesRatio() public {
        if (morpho.totalBorrow(id) == 0) return;
        assertGe(morpho.totalBorrowShares(id) / morpho.totalBorrow(id), SharesMathLib.VIRTUAL_SHARES);
    }
}
