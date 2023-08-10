// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/forge/BlueInvariantBase.t.sol";

contract SinglePositionConstantPriceInvariantTest is InvariantBaseTest {
    using FixedPointMathLib for uint256;
    using SharesMath for uint256;

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

        borrowableOracle.setPrice(1e18);
        collateralOracle.setPrice(1e18);
    }

    function _approveSendersTransfers(address[] memory senders) internal {
        for (uint256 i; i < senders.length; ++i) {
            vm.startPrank(senders[i]);
            borrowableAsset.approve(address(blue), type(uint256).max);
            collateralAsset.approve(address(blue), type(uint256).max);
            vm.stopPrank();
        }
    }

    function newBlock(uint8 elapsed) public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + elapsed);
    }

    function changePrice(uint256 variation, bool add, bool borrowable) public {
        // price variation bounded between 2% and 20%
        variation = bound(variation, 2e16, 2e17);
        if (borrowable) {
            uint256 currentPrice = IOracle(market.borrowableOracle).price();
            uint256 priceVariation = variation.mulWadDown(currentPrice);
            if (add) {
                borrowableOracle.setPrice(currentPrice + priceVariation);
            } else {
                borrowableOracle.setPrice(currentPrice - priceVariation);
            }
        } else {
            uint256 currentPrice = IOracle(market.collateralOracle).price();
            uint256 priceVariation = variation.mulWadDown(currentPrice);
            if (add) {
                collateralOracle.setPrice(currentPrice + priceVariation);
            } else {
                collateralOracle.setPrice(currentPrice - priceVariation);
            }
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
        blue.supply(market, amount, msg.sender, hex"");
    }

    function withdrawOnBlue(uint256 amount) public {
        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        if (blue.supplyShares(id, msg.sender) == 0) return;
        if (availableLiquidity == 0) return;

        uint256 supplierBalance =
            blue.supplyShares(id, msg.sender).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        amount = bound(amount, 1, min(supplierBalance, availableLiquidity));

        vm.prank(msg.sender);
        blue.withdraw(market, amount, msg.sender, msg.sender);
    }

    function withdrawOnBlueOnBehalf(uint256 amount, address seed) public {
        uint256 availableLiquidity = blue.totalSupply(id) - blue.totalBorrow(id);
        if (availableLiquidity == 0) return;

        address[] memory senders = targetSenders();
        address onBehalf = _randomSenderToWithdrawOnBehalf(senders, seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 supplierBalance =
            blue.supplyShares(id, onBehalf).toAssetsDown(blue.totalSupply(id), blue.totalSupplyShares(id));
        if (supplierBalance == 0) {
            amount = bound(amount, 1, min(supplierBalance, availableLiquidity));
        }

        vm.prank(msg.sender);
        blue.withdraw(market, amount, onBehalf, msg.sender);
    }

    function borrowOnBlue(uint256 amount) public {
        //supply collateral to accrue interests
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");

        uint256 availableSupply = blue.totalSupply(id) - blue.totalBorrow(id);
        if (availableSupply == 0 || blue.collateral(id, msg.sender) == 0 || !isHealthy(market, id, msg.sender)) return;

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        uint256 totalBorrowPower = blue.collateral(id, msg.sender).mulWadDown(collateralPrice).mulWadDown(market.lltv);
        uint256 alreadyBorrowed = blue.borrowShares(id, msg.sender).toAssetsUp(
            blue.totalBorrow(id), blue.totalBorrowShares(id)
        ).mulWadUp(borrowablePrice);
        uint256 currentBorrowPower = totalBorrowPower - alreadyBorrowed;

        if (currentBorrowPower == 0) return;

        amount = bound(amount, 1, min(currentBorrowPower, availableSupply));

        vm.prank(msg.sender);
        blue.borrow(market, amount, msg.sender, msg.sender);
    }

    function borrowOnBlueOnBehalf(uint256 amount, address seed) public {
        //supply collateral to accrue interests
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");

        uint256 availableSupply = blue.totalSupply(id) - blue.totalBorrow(id);
        if (availableSupply == 0) return;

        address[] memory senders = targetSenders();
        address onBehalf = _randomSenderToBorrowOnBehalf(senders, seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();
        uint256 totalBorrowPower = blue.collateral(id, onBehalf).mulWadDown(collateralPrice).mulWadDown(market.lltv);
        uint256 alreadyBorrowed = blue.borrowShares(id, onBehalf).toAssetsUp(
            blue.totalBorrow(id), blue.totalBorrowShares(id)
        ).mulWadUp(borrowablePrice);
        uint256 currentBorrowPower = totalBorrowPower - alreadyBorrowed;

        if (currentBorrowPower == 0) return;

        amount = bound(amount, 1, min(currentBorrowPower, availableSupply));

        vm.prank(msg.sender);
        blue.borrow(market, amount, onBehalf, msg.sender);
    }

    function repayOnBlue(uint256 amount) public {
        uint256 borrowedAmount =
            blue.borrowShares(id, msg.sender).toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id));
        if (borrowedAmount == 0) return;
        amount = bound(amount, 1, borrowedAmount);
        borrowableAsset.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        blue.repay(market, amount, msg.sender, hex"");
    }

    function repayOnBlueOnBehalf(uint256 amount, address seed) public {
        address[] memory senders = targetSenders();
        address onBehalf = _randomSenderToRepayOnBehalf(senders, seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 borrowedAmount =
            blue.borrowShares(id, onBehalf).toAssetsDown(blue.totalBorrow(id), blue.totalBorrowShares(id));
        if (borrowedAmount == 0) return;
        amount = bound(amount, 1, borrowedAmount);

        borrowableAsset.setBalance(msg.sender, amount);
        vm.prank(msg.sender);
        blue.repay(market, amount, onBehalf, hex"");
    }

    function supplyCollateralOnBlue(uint256 amount) public {
        amount = bound(amount, 1, 2 ** 64);
        collateralAsset.setBalance(msg.sender, amount);

        vm.prank(msg.sender);
        blue.supplyCollateral(market, amount, msg.sender, hex"");
    }

    function withdrawCollateralOnBlue(uint256 amount) public {
        //supply collateral to accrue interests
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");

        if (blue.collateral(id, msg.sender) == 0 || !isHealthy(market, id, msg.sender)) return;

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        uint256 borrowPower = blue.collateral(id, msg.sender).mulWadDown(collateralPrice).mulWadDown(market.lltv);
        uint256 borrowed = blue.borrowShares(id, msg.sender).toAssetsUp(
            blue.totalBorrow(id), blue.totalBorrowShares(id)
        ).mulWadUp(borrowablePrice);
        uint256 withdrawableCollateral = (borrowPower - borrowed).divWadDown(collateralPrice);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        blue.withdrawCollateral(market, amount, msg.sender, msg.sender);
    }

    function withdrawCollateralOnBlueOnBehalf(uint256 amount, address seed) public {
        //supply collateral to accrue interests
        collateralAsset.setBalance(address(this), 1);
        blue.supplyCollateral(market, 1, address(this), hex"");

        address[] memory senders = targetSenders();
        address onBehalf = _randomSenderToWithdrawCollateralOnBehalf(senders, seed, msg.sender);
        if (onBehalf == address(0)) return;

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        uint256 borrowPower = blue.collateral(id, onBehalf).mulWadDown(collateralPrice).mulWadDown(market.lltv);
        uint256 borrowed = blue.borrowShares(id, onBehalf).toAssetsUp(blue.totalBorrow(id), blue.totalBorrowShares(id))
            .mulWadUp(borrowablePrice);
        uint256 withdrawableCollateral = (borrowPower - borrowed).divWadDown(collateralPrice);

        if (withdrawableCollateral == 0) return;
        amount = bound(amount, 1, withdrawableCollateral);

        vm.prank(msg.sender);
        blue.withdrawCollateral(market, amount, onBehalf, msg.sender);
    }

    function liquidateOnBlue(uint256 seized, address seed) public {
        address[] memory senders = targetSenders();
        user = _randomSenderToLiquidate(senders, seed);
        if (user == address(0)) return;
        seized = bound(seized, 1, blue.collateral(id, user));

        uint256 collateralPrice = IOracle(market.collateralOracle).price();
        uint256 borrowablePrice = IOracle(market.borrowableOracle).price();

        uint256 incentive = FixedPointMathLib.WAD
            + ALPHA.mulWadDown(FixedPointMathLib.WAD.divWadDown(market.lltv) - FixedPointMathLib.WAD);
        uint256 repaid = seized.mulWadUp(collateralPrice).divWadUp(incentive).divWadUp(borrowablePrice);
        uint256 repaidShares = repaid.toSharesDown(blue.totalBorrow(id), blue.totalBorrowShares(id));

        if (repaidShares > blue.borrowShares(id, user)) {
            seized = seized / 2;
        }
        borrowableAsset.setBalance(msg.sender, repaid);

        vm.prank(msg.sender);
        blue.liquidate(market, user, seized, hex"");
    }

    function invariantSupplyShares() public {
        address[] memory senders = targetSenders();
        assertEq(sumUsersSupplyShares(senders), blue.totalSupplyShares(id));
    }

    function invariantBorrowShares() public {
        address[] memory senders = targetSenders();
        assertEq(sumUsersBorrowShares(senders), blue.totalBorrowShares(id));
    }

    function invariantTotalSupply() public {
        address[] memory senders = targetSenders();
        assertLe(sumUsersSuppliedAmounts(senders), blue.totalSupply(id));
    }

    function invariantTotalBorrow() public {
        address[] memory senders = targetSenders();
        assertGe(sumUsersBorrowedAmounts(senders), blue.totalBorrow(id));
    }

    function invariantTotalBorrowLessThanTotalSupply() public {
        assertGe(blue.totalSupply(id), blue.totalBorrow(id));
    }

    function invariantBlueBalance() public {
        assertEq(blue.totalSupply(id) - blue.totalBorrow(id), borrowableAsset.balanceOf(address(blue)));
    }
}
