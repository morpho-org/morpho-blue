// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../InvariantTest.sol";

contract SingleMarketChangingPriceInvariantTest is InvariantTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    address user;

    function setUp() public virtual override {
        _weightSelector(this.changePrice.selector, 5);
        _weightSelector(this.setFeeNoRevert.selector, 2);
        _weightSelector(this.supplyOnBehalfNoRevert.selector, 20);
        _weightSelector(this.withdrawOnBehalfNoRevert.selector, 10);
        _weightSelector(this.borrowOnBehalfNoRevert.selector, 10);
        _weightSelector(this.repayOnBehalfNoRevert.selector, 4);
        _weightSelector(this.supplyCollateralNoRevert.selector, 20);
        _weightSelector(this.withdrawCollateralOnBehalfNoRevert.selector, 10);

        super.setUp();

        _targetDefaultSenders();

        oracle.setPrice(1e36);
    }

    /* ACTIONS */

    function changePrice(uint256 variation) public {
        // price variation bounded between -20% and +20%
        variation = bound(variation, 0.8e18, 1.2e18);
        uint256 currentPrice = IOracle(marketParams.oracle).price();
        oracle.setPrice(currentPrice.wMulDown(variation));
    }

    function setFeeNoRevert(uint256 newFee) public {
        newFee = bound(newFee, 0, MAX_FEE);

        vm.prank(OWNER);
        morpho.setFee(marketParams, newFee);
    }

    function supplyOnBehalfNoRevert(uint256 assets, uint256 seed) public {
        address onBehalf = _randomCandidate(targetSenders(), seed);

        assets = _boundSupplyAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        borrowableToken.setBalance(msg.sender, assets);

        vm.prank(msg.sender);
        morpho.supply(marketParams, assets, 0, onBehalf, hex"");
    }

    function withdrawOnBehalfNoRevert(uint256 assets, uint256 seed, address receiver) public {
        address onBehalf = _randomSupplier(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        assets = _boundWithdrawAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        if (onBehalf != msg.sender) {
            vm.prank(onBehalf);
            morpho.setAuthorization(msg.sender, true);
        }

        vm.prank(msg.sender);
        morpho.withdraw(marketParams, assets, 0, onBehalf, receiver);
    }

    function borrowOnBehalfNoRevert(uint256 assets, uint256 seed, address receiver) public {
        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        assets = _boundBorrowAssets(marketParams, onBehalf, assets);
        if (assets == 0) return;

        if (onBehalf != msg.sender) {
            vm.prank(onBehalf);
            morpho.setAuthorization(msg.sender, true);
        }

        vm.prank(msg.sender);
        morpho.borrow(marketParams, assets, 0, onBehalf, receiver);
    }

    function repayOnBehalfNoRevert(uint256 shares, uint256 seed) public {
        address onBehalf = _randomBorrower(targetSenders(), marketParams, seed);
        if (onBehalf == address(0)) return;

        uint256 borrowShares = morpho.borrowShares(id, onBehalf);
        shares = bound(shares, 1, borrowShares);
        uint256 repaidAmount = shares.toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));
        if (repaidAmount == 0) return;

        borrowableToken.setBalance(msg.sender, repaidAmount);
        vm.prank(msg.sender);
        morpho.repay(marketParams, 0, shares, onBehalf, hex"");
    }

    function supplyCollateralNoRevert(uint256 amount) public {
        amount = bound(amount, 1, MAX_TEST_AMOUNT);
        collateralToken.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(marketParams, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnBehalfNoRevert(uint256 amount, uint256 seed) public {
        address onBehalf = _randomHealthyCollateralSupplier(targetSenders(), marketParams, seed);
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

        if (onBehalf != msg.sender) {
            vm.prank(onBehalf);
            morpho.setAuthorization(msg.sender, true);
        }

        vm.prank(msg.sender);
        morpho.withdrawCollateral(marketParams, amount, onBehalf, msg.sender);
    }

    function liquidateNoRevert(uint256 seized, uint256 seed) public {
        user = _randomUnhealthyBorrower(targetSenders(), marketParams, seed);
        if (user == address(0)) return;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();

        uint256 repaid =
            seized.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).wDivUp(_liquidationIncentive(marketParams.lltv));
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
        assertEq(sumSupplyShares(targetSenders()), morpho.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        assertEq(sumBorrowShares(targetSenders()), morpho.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        assertLe(sumSupplyAssets(targetSenders()), morpho.totalSupplyAssets(id));
    }

    function invariantTotalBorrow() public {
        assertGe(sumBorrowAssets(targetSenders()), morpho.totalBorrowAssets(id));
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
