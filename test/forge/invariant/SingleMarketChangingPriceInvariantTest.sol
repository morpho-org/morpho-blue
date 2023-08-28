// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SingleMarketChangingPriceInvariantTest is InvariantTest {
    using MathLib for uint256;
    using MorphoLib for Morpho;
    using SharesMathLib for uint256;

    address user;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _approveSendersTransfers(targetSenders());

        _weightSelector(this.newBlock.selector, 20);
        _weightSelector(this.changePrice.selector, 5);
        _weightSelector(this.setFeeNoRevert.selector, 2);
        _weightSelector(this.supplyNoRevert.selector, 20);
        _weightSelector(this.withdrawNoRevert.selector, 5);
        _weightSelector(this.withdrawOnBehalfNoRevert.selector, 5);
        _weightSelector(this.borrowNoRevert.selector, 5);
        _weightSelector(this.borrowOnBehalfNoRevert.selector, 5);
        _weightSelector(this.repayNoRevert.selector, 2);
        _weightSelector(this.repayOnBehalfNoRevert.selector, 2);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralNoRevert.selector, 5);
        _weightSelector(this.withdrawCollateralOnBehalfNoRevert.selector, 5);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));

        oracle.setPrice(1e36);
    }

    /* ACTIONS */

    function changePrice(uint256 variation) public {
        // price variation bounded between -20% and +20%
        variation = bound(variation, 0.8e18, 1.2e18);
        uint256 currentPrice = IOracle(marketParams.oracle).price();
        oracle.setPrice(currentPrice.wMulDown(variation));
    }

    function setFeeNoRevert(uint256 newFee) public setCorrectBlock {
        newFee = bound(newFee, 0, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function supplyNoRevert(uint256 amount) public setCorrectBlock {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        borrowableToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supply(marketParams, amount, 0, msg.sender, hex"");
    }

    function withdrawNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (morpho.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        uint256 supplierBalance =
            morpho.supplyShares(id, msg.sender).toAssetsDown(morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id));

        if (supplierBalance == 0) return;
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function withdrawOnBehalfNoRevert(uint256 amount, address seed) public setCorrectBlock {
        _accrueInterest(marketParams);

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
        morpho.withdraw(marketParams, amount, 0, onBehalf, msg.sender);
    }

    function borrowNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (availableLiquidity == 0 || morpho.collateral(id, msg.sender) == 0 || !isHealthy(id, msg.sender)) {
            return;
        }
        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 totalBorrowPower = morpho.collateral(id, msg.sender).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE)
            .wMulDown(marketParams.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, msg.sender).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - borrowed;

        if (currentBorrowPower == 0) return;
        amount = bound(amount, 1, min(currentBorrowPower, availableLiquidity));

        vm.prank(msg.sender);
        morpho.borrow(marketParams, amount, 0, msg.sender, msg.sender);
    }

    function borrowOnBehalfNoRevert(uint256 amount, address seed) public setCorrectBlock {
        _accrueInterest(marketParams);

        uint256 availableLiquidity = morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id);
        if (availableLiquidity == 0) return;

        address onBehalf = _randomSenderToBorrowOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 totalBorrowPower =
            morpho.collateral(id, onBehalf).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, onBehalf).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 currentBorrowPower = totalBorrowPower - borrowed;

        if (currentBorrowPower == 0) return;
        amount = bound(amount, 1, min(currentBorrowPower, availableLiquidity));

        vm.prank(msg.sender);
        morpho.borrow(marketParams, amount, 0, onBehalf, msg.sender);
    }

    function repayNoRevert(uint256 shares) public setCorrectBlock {
        _accrueInterest(marketParams);

        uint256 borrowShares = morpho.borrowShares(id, msg.sender);
        if (borrowShares == 0) return;

        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);

        vm.prank(msg.sender);
        morpho.repay(marketParams, 0, shares, msg.sender, hex"");
    }

    function repayOnBehalfNoRevert(uint256 shares, address seed) public setCorrectBlock {
        _accrueInterest(marketParams);

        address onBehalf = _randomSenderToRepayOnBehalf(targetSenders(), seed);
        if (onBehalf == address(0)) return;

        uint256 borrowShares = morpho.borrowShares(id, onBehalf);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);
        vm.prank(msg.sender);
        morpho.repay(marketParams, 0, shares, onBehalf, hex"");
    }

    function supplyCollateralNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, amount, msg.sender, hex"");
    }

    function withdrawCollateralNoRevert(uint256 amount) public setCorrectBlock {
        _accrueInterest(marketParams);

        if (morpho.collateral(id, msg.sender) == 0 || !isHealthy(id, msg.sender)) return;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 borrowPower = morpho.collateral(id, msg.sender).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(
            marketParams.lltv
        );
        uint256 borrowed =
            morpho.borrowShares(id, msg.sender).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 withdrawableCollateral =
            (borrowPower - borrowed).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice).wDivDown(marketParams.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, amount, msg.sender, msg.sender);
    }

    function withdrawCollateralOnBehalfNoRevert(uint256 amount, address seed) public setCorrectBlock {
        _accrueInterest(marketParams);

        address onBehalf = _randomSenderToWithdrawCollateralOnBehalf(targetSenders(), seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 borrowPower =
            morpho.collateral(id, onBehalf).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);
        uint256 borrowed =
            morpho.borrowShares(id, onBehalf).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        uint256 withdrawableCollateral =
            (borrowPower - borrowed).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice).wDivDown(marketParams.lltv);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, amount, onBehalf, msg.sender);
    }

    function liquidateNoRevert(uint256 seized, address seed) public setCorrectBlock {
        _accrueInterest(marketParams);

        user = _randomSenderToLiquidate(targetSenders(), seed);
        if (user == address(0)) return;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 repaid =
            seized.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(_liquidationIncentiveFactor(marketParams.lltv));
        uint256 repaidShares = repaid.toSharesDown(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));

        if (repaidShares > morpho.borrowShares(id, user)) {
            seized = seized / 2;
        }
        borrowableToken.setBalance(msg.sender, repaid);

        vm.prank(msg.sender);
        morpho.liquidate(marketParams, user, seized, 0, hex"");
    }

    /* INVARIANTS */

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
        assertGe(
            borrowableToken.balanceOf(address(morpho)), morpho.totalSupplyAssets(id) - morpho.totalBorrowAssets(id)
        );
    }
}
