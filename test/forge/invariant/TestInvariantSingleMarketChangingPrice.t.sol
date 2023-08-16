// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantBase.sol";

contract SingleMarketChangingPriceInvariantTest is InvariantBaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    address user;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());

        _weightSelector(this.supplyOnMorpho.selector, 20);
        _weightSelector(this.withdrawOnMorpho.selector, 5);
        _weightSelector(this.withdrawOnMorphoOnBehalf.selector, 5);
        _weightSelector(this.borrowOnMorpho.selector, 5);
        _weightSelector(this.borrowOnMorphoOnBehalf.selector, 5);
        _weightSelector(this.repayOnMorpho.selector, 2);
        _weightSelector(this.repayOnMorphoOnBehalf.selector, 2);
        _weightSelector(this.supplyCollateralOnMorpho.selector, 20);
        _weightSelector(this.withdrawCollateralOnMorpho.selector, 5);
        _weightSelector(this.withdrawCollateralOnMorphoOnBehalf.selector, 5);
        _weightSelector(this.newBlock.selector, 5);
        _weightSelector(this.changePrice.selector, 5);
        _weightSelector(this.setMarketFee.selector, 1);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));

        oracle.setPrice(1e36);
    }

    function newBlock(uint8 elapsed) public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);
    }

    function changePrice(uint256 variation, bool add) public {
        // price variation bounded between 2% and 20%
        variation = bound(variation, 2e16, 2e17);
        uint256 currentPrice = IOracle(market.oracle).price();
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
        if (supplierBalance.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;
        amount = bound(amount, 1, min(supplierBalance.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        morpho.withdraw(market, amount, 0, msg.sender, msg.sender);
    }

    function withdrawOnMorphoOnBehalf(uint256 amount, address seed) public {
        morpho.accrueInterests(market);

        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToWithdrawOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;
        if (morpho.supplyShares(id, onBehalf) != 0) return;

        uint256 supplierBalance =
            morpho.supplyShares(id, onBehalf).toAssetsDown(morpho.totalSupply(id), morpho.totalSupplyShares(id));
        if (supplierBalance.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;
        amount = bound(amount, 1, min(supplierBalance.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        morpho.withdraw(market, amount, 0, onBehalf, msg.sender);
    }

    function borrowOnMorpho(uint256 amount) public {
        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (availableLiquidity == 0 || morpho.collateral(id, msg.sender) == 0 || !isHealthy(market, id, msg.sender)) {
            return;
        }

        morpho.accrueInterests(market);
        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 totalBorrowPower =
            morpho.collateral(id, msg.sender).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 alreadyBorrowed =
            morpho.borrowShares(id, msg.sender).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - alreadyBorrowed;

        if (currentBorrowPower.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;

        amount = bound(amount, 1, min(currentBorrowPower.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        morpho.borrow(market, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorphoOnBehalf(uint256 amount, address seed) public {
        morpho.accrueInterests(market);

        uint256 availableLiquidity = morpho.totalSupply(id) - morpho.totalBorrow(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToBorrowOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 totalBorrowPower =
            morpho.collateral(id, onBehalf).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 alreadyBorrowed =
            morpho.borrowShares(id, onBehalf).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - alreadyBorrowed;

        if (currentBorrowPower.wMulDown(95e16) == 0) return;
        if (availableLiquidity.wMulDown(95e16) == 0) return;

        amount = bound(amount, 1, min(currentBorrowPower.wMulDown(95e16), availableLiquidity.wMulDown(95e16)));

        vm.prank(msg.sender);
        morpho.borrow(market, amount, 0, onBehalf, msg.sender);
    }

    function repayOnMorpho(uint256 shares) public {
        uint256 borrowShares = morpho.borrowShares(id, msg.sender);
        if (borrowShares == 0) return;

        morpho.accrueInterests(market);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);

        vm.prank(msg.sender);
        morpho.repay(market, 0, shares, msg.sender, hex"");
    }

    function repayOnMorphoOnBehalf(uint256 shares, address seed) public {
        morpho.accrueInterests(market);

        address onBehalf = _randomSenderToRepayOnBehalf(targetSenders(), seed);
        if (onBehalf == address(0)) return;

        uint256 borrowShares = morpho.borrowShares(id, onBehalf);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);
        vm.prank(msg.sender);
        morpho.repay(market, 0, shares, onBehalf, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount) public {
        if (morpho.collateral(id, msg.sender) == 0 || !isHealthy(market, id, msg.sender)) return;

        morpho.accrueInterests(market);

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 borrowPower =
            morpho.collateral(id, msg.sender).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, msg.sender).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        uint256 withdrawableCollateral =
            (borrowPower - borrowed).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice).wDivDown(market.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function withdrawCollateralOnMorphoOnBehalf(uint256 amount, address seed) public {
        morpho.accrueInterests(market);

        address onBehalf = _randomSenderToWithdrawCollateralOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 borrowPower =
            morpho.collateral(id, onBehalf).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, onBehalf).toAssetsUp(morpho.totalBorrow(id), morpho.totalBorrowShares(id));
        uint256 withdrawableCollateral =
            (borrowPower - borrowed).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice).wDivDown(market.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market, amount, onBehalf, msg.sender);
    }

    function liquidateOnMorpho(uint256 seized, address seed) public {
        morpho.accrueInterests(market);

        user = _randomSenderToLiquidate(targetSenders(), seed);
        if (user == address(0)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 repaid =
            seized.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(_liquidationIncentiveFactor(market.lltv));
        uint256 repaidShares = repaid.toSharesDown(morpho.totalBorrow(id), morpho.totalBorrowShares(id));

        if (repaidShares > morpho.borrowShares(id, user)) {
            seized = seized / 2;
        }
        borrowableToken.setBalance(msg.sender, repaid);

        vm.prank(msg.sender);
        morpho.liquidate(market, user, seized, hex"");
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
}
