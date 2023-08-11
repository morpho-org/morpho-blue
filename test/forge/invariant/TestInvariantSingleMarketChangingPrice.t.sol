// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueInvariantBase.t.sol";

contract SinglePositionConstantPriceInvariantTest is InvariantBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;

    address user;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());

        _weightSelector(this.supplyOnBlue.selector, 20);
        _weightSelector(this.withdrawOnBlue.selector, 5);
        _weightSelector(this.withdrawOnBlueOnBehalf.selector, 5);
        _weightSelector(this.borrowOnBlue.selector, 5);
        _weightSelector(this.borrowOnBlueOnBehalf.selector, 5);
        _weightSelector(this.repayOnBlue.selector, 2);
        _weightSelector(this.repayOnBlueOnBehalf.selector, 2);
        _weightSelector(this.supplyCollateralOnBlue.selector, 20);
        _weightSelector(this.withdrawCollateralOnBlue.selector, 5);
        _weightSelector(this.withdrawCollateralOnBlueOnBehalf.selector, 5);
        _weightSelector(this.newBlock.selector, 5);
        _weightSelector(this.changePrice.selector, 5);
        _weightSelector(this.setMarketFee.selector, 1);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));

        oracle.setPrice(1e18);
    }

    function newBlock(uint8 elapsed) public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);
    }

    function changePrice(uint256 variation, bool add) public {
        // price variation bounded between 2% and 20%
        variation = bound(variation, 2e16, 2e17);
        (uint256 currentPrice,) = IOracle(market.oracle).price();
        uint256 priceVariation = currentPrice.wMulDown(variation);
        if (add) {
            oracle.setPrice(currentPrice + priceVariation);
        } else {
            oracle.setPrice(currentPrice - priceVariation);
        }
    }

    function setMarketFee(uint256 newFee) public {
        newFee = bound(newFee, 0, MAX_FEE);

        vm.prank(OWNER);
        blue.setFee(market, newFee);
    }

    function supplyOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        borrowableAsset.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        blue.supply(market, amount, 0, msg.sender, hex"");
    }

    function withdrawOnBlue(uint256 amount) public {
        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        if (blue.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        _accrueInterest(market);
        uint256 supplierBalance =
            blue.supplyShares(id, msg.sender).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        if (supplierBalance.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;
        amount = bound(amount, 1, min(supplierBalance.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        blue.withdraw(market, amount, 0, msg.sender, msg.sender);
    }

    function withdrawOnBlueOnBehalf(uint256 amount, address seed) public {
        _accrueInterest(market);

        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToWithdrawOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;
        if (blue.supplyShares(id, onBehalf) != 0) return;

        uint256 supplierBalance =
            blue.supplyShares(id, onBehalf).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        if (supplierBalance.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;
        amount = bound(amount, 1, min(supplierBalance.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        blue.withdraw(market, amount, 0, onBehalf, msg.sender);
    }

    function borrowOnBlue(uint256 amount) public {
        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        if (availableLiquidity == 0 || blue.collateral(id, msg.sender) == 0 || !isHealthy(market, id, msg.sender)) {
            return;
        }

        _accrueInterest(market);
        (uint256 collateralPrice,) = IOracle(market.oracle).price();

        uint256 totalBorrowPower = blue.collateral(id, msg.sender).wMulDown(collateralPrice).wMulDown(market.lltv);
        uint256 alreadyBorrowed =
            blue.borrowShares(id, msg.sender).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - alreadyBorrowed;

        if (currentBorrowPower.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;

        amount = bound(amount, 1, min(currentBorrowPower.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        blue.borrow(market, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnBlueOnBehalf(uint256 amount, address seed) public {
        _accrueInterest(market);

        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToBorrowOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        (uint256 collateralPrice,) = IOracle(market.oracle).price();

        uint256 totalBorrowPower = blue.collateral(id, onBehalf).wMulDown(collateralPrice).wMulDown(market.lltv);
        uint256 alreadyBorrowed =
            blue.borrowShares(id, onBehalf).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - alreadyBorrowed;

        if (currentBorrowPower.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;

        amount = bound(amount, 1, min(currentBorrowPower.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        blue.borrow(market, amount, 0, onBehalf, msg.sender);
    }

    function repayOnBlue(uint256 shares) public {
        uint256 borrowShares = blue.borrowShares(id, msg.sender);
        if (borrowShares == 0) return;

        _accrueInterest(market);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableAsset.setBalance(msg.sender, repaidAmount);

        vm.prank(msg.sender);
        blue.repay(market, 0, shares, msg.sender, hex"");
    }

    function repayOnBlueOnBehalf(uint256 shares, address seed) public {
        _accrueInterest(market);

        address onBehalf = _randomSenderToRepayOnBehalf(targetSenders(), seed);
        if (onBehalf == address(0)) return;

        uint256 borrowShares = blue.borrowShares(id, onBehalf);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableAsset.setBalance(msg.sender, repaidAmount);
        vm.prank(msg.sender);
        blue.repay(market, 0, shares, onBehalf, hex"");
    }

    function supplyCollateralOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        blue.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnBlue(uint256 amount) public {
        if (blue.collateral(id, msg.sender) == 0 || !isHealthy(market, id, msg.sender)) return;

        _accrueInterest(market);

        (uint256 collateralPrice,) = IOracle(market.oracle).price();

        uint256 borrowPower = blue.collateral(id, msg.sender).wMulDown(collateralPrice).wMulDown(market.lltv);
        uint256 borrowed =
            blue.borrowShares(id, msg.sender).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        uint256 withdrawableCollateral = (borrowPower - borrowed).wDivDown(collateralPrice).wDivDown(market.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        blue.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function withdrawCollateralOnBlueOnBehalf(uint256 amount, address seed) public {
        _accrueInterest(market);

        address onBehalf = _randomSenderToWithdrawCollateralOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        (uint256 collateralPrice,) = IOracle(market.oracle).price();

        uint256 borrowPower = blue.collateral(id, onBehalf).wMulDown(collateralPrice).wMulDown(market.lltv);
        uint256 borrowed = blue.borrowShares(id, onBehalf).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id));
        uint256 withdrawableCollateral = (borrowPower - borrowed).wDivDown(collateralPrice).wDivDown(market.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        blue.withdrawCollateral(market, amount, onBehalf, msg.sender);
    }

    function liquidateOnBlue(uint256 seized, address seed) public {
        _accrueInterest(market);

        user = _randomSenderToLiquidate(targetSenders(), seed);
        if (user == address(0)) return;

        (uint256 collateralPrice,) = IOracle(market.oracle).price();

        uint256 incentive = WAD + ALPHA.wMulDown(WAD.wDivDown(market.lltv) - WAD);
        uint256 repaid = seized.wMulDown(collateralPrice).wDivDown(incentive);
        uint256 repaidShares = repaid.toSharesDown(blue.totalBorrow(id), blue.totalBorrowShares(id));

        if (repaidShares > blue.borrowShares(id, user)) {
            seized = seized / 2;
        }
        borrowableAsset.setBalance(msg.sender, repaid);

        vm.prank(msg.sender);
        blue.liquidate(market, user, seized, hex"");
    }

    function invariantSupplyShares() public {
        assertEq(sumUsersSupplyShares(targetSenders()), blue.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(sumUsersBorrowShares(targetSenders()), blue.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        assertLe(sumUsersSuppliedAmounts(targetSenders()), blue.totalSupply(id));
    }

    function invariantTotalBorrow() public {
        assertGe(sumUsersBorrowedAmounts(targetSenders()), blue.totalBorrow(id));
    }

    function invariantTotalBorrowLessThanTotalSupply() public {
        assertGe(blue.totalSupply(id), blue.totalBorrow(id));
    }

    function invariantBlueBalance() public {
        assertEq(blue.totalSupply(id) - blue.totalBorrow(id), borrowableAsset.balanceOf(address(blue)));
    }
}
