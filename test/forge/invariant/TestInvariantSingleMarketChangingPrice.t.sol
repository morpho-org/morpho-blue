// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/InvariantTest.sol";

contract SingleMarketChangingPriceInvariantTest is InvariantTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
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
        _weightSelector(this.newBlock.selector, 20);
        _weightSelector(this.changePrice.selector, 5);
        _weightSelector(this.setMarketFee.selector, 2);

        blockNumber = block.number;
        timestamp = block.timestamp;

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));

        oracle.setPrice(1e36);
    }

    function changePrice(uint256 variation) public {
        // price variation bounded between -20% and +20%
        variation = bound(variation, 0.8e18, 1.2e18);
        uint256 currentPrice = IOracle(market.oracle).price();
        oracle.setPrice(currentPrice.wMulDown(variation));
    }

    function setMarketFee(uint256 newFee) public setCorrectBlock {
        newFee = bound(newFee, 0, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(market, newFee);
    }

    function supplyOnMorpho(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supply(market, amount, 0, msg.sender, hex"");
    }

    function withdrawOnMorpho(uint256 amount) public setCorrectBlock {
        morpho.accrueInterest(market);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (morpho.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        uint256 supplierBalance =
            morpho.supplyShares(id, msg.sender).toAssetsDown(morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id));

        if (supplierBalance == 0) return;
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(market, amount, 0, msg.sender, msg.sender);
    }

    function withdrawOnMorphoOnBehalf(uint256 amount, address seed) public setCorrectBlock {
        morpho.accrueInterest(market);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToWithdrawOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;
        if (morpho.supplyShares(id, onBehalf) != 0) return;
        uint256 supplierBalance =
            morpho.supplyShares(id, onBehalf).toAssetsDown(morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id));

        if (supplierBalance == 0) return;
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(market, amount, 0, onBehalf, msg.sender);
    }

    function borrowOnMorpho(uint256 amount) public setCorrectBlock {
        morpho.accrueInterest(market);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (availableLiquidity == 0 || morpho.collateral(id, msg.sender) == 0 || !isHealthy(id, msg.sender)) {
            return;
        }
        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 totalBorrowPower =
            morpho.collateral(id, msg.sender).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, msg.sender).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - borrowed;

        if (currentBorrowPower == 0) return;
        amount = bound(amount, 1, min(currentBorrowPower, availableLiquidity));

        vm.prank(msg.sender);
        morpho.borrow(market, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnMorphoOnBehalf(uint256 amount, address seed) public setCorrectBlock {
        morpho.accrueInterest(market);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToBorrowOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 totalBorrowPower =
            morpho.collateral(id, onBehalf).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, onBehalf).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - borrowed;

        if (currentBorrowPower == 0) return;
        amount = bound(amount, 1, min(currentBorrowPower, availableLiquidity));

        vm.prank(msg.sender);
        morpho.borrow(market, amount, 0, onBehalf, msg.sender);
    }

    function repayOnMorpho(uint256 shares) public setCorrectBlock {
        morpho.accrueInterest(market);

        uint256 borrowShares = morpho.borrowShares(id, msg.sender);
        if (borrowShares == 0) return;

        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);

        vm.prank(msg.sender);
        morpho.repay(market, 0, shares, msg.sender, hex"");
    }

    function repayOnMorphoOnBehalf(uint256 shares, address seed) public setCorrectBlock {
        morpho.accrueInterest(market);

        address onBehalf = _randomSenderToRepayOnBehalf(targetSenders(), seed);
        if (onBehalf == address(0)) return;

        uint256 borrowShares = morpho.borrowShares(id, onBehalf);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);
        vm.prank(msg.sender);
        morpho.repay(market, 0, shares, onBehalf, hex"");
    }

    function supplyCollateralOnMorpho(uint256 amount) public setCorrectBlock {
        morpho.accrueInterest(market);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnMorpho(uint256 amount) public setCorrectBlock {
        morpho.accrueInterest(market);

        if (morpho.collateral(id, msg.sender) == 0 || !isHealthy(id, msg.sender)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 borrowPower =
            morpho.collateral(id, msg.sender).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, msg.sender).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 withdrawableCollateral =
            (borrowPower - borrowed).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice).wDivDown(market.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function withdrawCollateralOnMorphoOnBehalf(uint256 amount, address seed) public setCorrectBlock {
        morpho.accrueInterest(market);

        address onBehalf = _randomSenderToWithdrawCollateralOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 borrowPower =
            morpho.collateral(id, onBehalf).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(market.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, onBehalf).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 withdrawableCollateral =
            (borrowPower - borrowed).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice).wDivDown(market.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market, amount, onBehalf, msg.sender);
    }

    function liquidateOnMorpho(uint256 seized, address seed) public setCorrectBlock {
        morpho.accrueInterest(market);

        user = _randomSenderToLiquidate(targetSenders(), seed);
        if (user == address(0)) return;

        uint256 collateralPrice = IOracle(market.oracle).price();

        uint256 repaid =
            seized.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(_liquidationIncentiveFactor(market.lltv));
        uint256 repaidShares = repaid.toSharesDown(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));

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
        assertLe(sumUsersSuppliedAmounts(targetSenders()), morpho.totalSupplyAssets(id));
    }

    function invariantTotalBorrow() public {
        assertGe(sumUsersBorrowedAmounts(targetSenders()), morpho.totalBorrowAssets(id));
    }

    function invariantTotalSupplyGreaterThanTotalBorrow() public {
        assertGe(morpho.totalSupplyAssets(id), morpho.totalBorrowAssets(id));
    }

    function invariantMorphoBalance() public {
        assertEq(
            morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id), borrowableToken.balanceOf(address(morpho))
        );
    }
}
