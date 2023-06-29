// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IBlueOracle} from "./interfaces/IBlueOracle.sol";
import {IBlueBorrowCallback} from "./interfaces/IBlueBorrowCallback.sol";
import {IBlueLiquidateCallback} from "./interfaces/IBlueLiquidateCallback.sol";
import {IInterestRatesManager} from "./interfaces/IInterestRatesManager.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Tranche} from "./libraries/Tranche.sol";
import {Account} from "./libraries/Account.sol";
import {Indexes} from "./libraries/Indexes.sol";
import {SignedMath} from "./libraries/SignedMath.sol";

contract Blue {
    using Account for bytes32;
    using WadRayMath for uint256;
    using Tranche for Tranche.Self;
    using Indexes for uint256;
    using SignedMath for uint256;

    struct Borrow {
        uint256 collateral;
        uint256 scaledBorrow;
        uint256 badDebtIndex;
    }

    struct Lend {
        uint256 scaledSupply;
        uint256 badDebtIndex;
    }

    struct LiquidationData {
        bytes32 account;
        uint256 amount;
    }

    address public immutable collateral;
    address public immutable borrowing;
    IBlueOracle public immutable oracle;
    IInterestRatesManager public immutable irm;

    mapping(bytes32 account => Lend) public lendings;
    mapping(bytes32 account => Borrow) public borrows;
    mapping(uint256 lltv => Tranche.Self) public tranches;

    constructor(
        address newCollateral,
        address newBorrowing,
        address newOracle,
        address newIrm,
        uint256[] memory lltvs
    ) {
        collateral = newCollateral;
        borrowing = newBorrowing;
        oracle = IBlueOracle(newOracle);
        irm = IInterestRatesManager(newIrm);

        for (uint256 i; i < lltvs.length; ++i) {
            tranches[lltvs[i]].initialize();
        }
    }

    function lend(bytes32 account, int256 supplyDelta) external {
        if (supplyDelta < 0) require(account.addr() == msg.sender, "unauthorized");

        Lend storage accountLend = lendings[account];

        Tranche.Self memory tranche = tranches[account.lltv()].cache();
        _updateIndexes(tranche, account.lltv());

        uint256 oldScaledSupply = accountLend.scaledSupply;

        if (supplyDelta == type(int256).min) {
            supplyDelta = tranche.updateSupplyFromScaled(-int256(oldScaledSupply));
            accountLend.scaledSupply = 0;
        } else {
            accountLend.scaledSupply = oldScaledSupply.sadd(tranche.updateSupplyFromNormalized(supplyDelta));
        }

        tranches[account.lltv()].commit(tranche);

        if (supplyDelta > 0) IERC20(borrowing).transferFrom(msg.sender, address(this), uint256(supplyDelta));
        else IERC20(borrowing).transfer(account.addr(), uint256(-supplyDelta));
    }

    function borrow(bytes32 account, int256 collateralDelta, int256 borrowDelta, bytes memory data) external {
        if (borrowDelta > 0 || collateralDelta < 0) require(msg.sender == account.addr(), "unauthorized");

        IBlueOracle.BlueOracleResult memory oracleResult = oracle.query();

        if (borrowDelta > 0) require(!oracleResult.disableBorrows, "borrow disabled");

        Borrow storage accountBorrow = borrows[account];

        Tranche.Self memory tranche = tranches[account.lltv()].cache();
        _updateIndexes(tranche, account.lltv());

        uint256 oldScaledBorrow = accountBorrow.scaledBorrow;

        if (borrowDelta == type(int256).min) {
            borrowDelta = tranche.updateBorrowFromScaled(-int256(oldScaledBorrow));
            accountBorrow.scaledBorrow = 0;
        } else {
            accountBorrow.scaledBorrow = oldScaledBorrow.sadd(tranche.updateBorrowFromNormalized(borrowDelta));
        }

        if (collateralDelta == type(int256).min) {
            collateralDelta = -int256(accountBorrow.collateral);
            accountBorrow.collateral = 0;
        } else {
            accountBorrow.collateral = accountBorrow.collateral.ssub(collateralDelta);
        }

        uint256 newCollateral = accountBorrow.collateral;
        uint256 newBorrow = accountBorrow.scaledBorrow.toNormalized(tranche.borrowIndex);
        require(computeLTV(newCollateral, newBorrow, oracleResult) < account.lltv(), "LTV > LLTV");

        if (collateralDelta < 0) IERC20(collateral).transfer(account.addr(), uint256(-collateralDelta));
        if (borrowDelta > 0) IERC20(borrowing).transfer(account.addr(), uint256(borrowDelta));

        tranches[account.lltv()].commit(tranche);

        if (data.length > 0) IBlueBorrowCallback(msg.sender).blueBorrowCallback(collateralDelta, borrowDelta, data);

        if (collateralDelta > 0) IERC20(collateral).transferFrom(msg.sender, address(this), uint256(collateralDelta));
        if (borrowDelta < 0) IERC20(borrowing).transferFrom(msg.sender, address(this), uint256(-borrowDelta));
    }

    function liquidate(LiquidationData[] calldata liquidationData, bytes calldata data)
        external
        returns (uint256 repaid, uint256 seized)
    {
        IBlueOracle.BlueOracleResult memory oracleResult = oracle.query();
        require(!oracleResult.disableLiquidations, "liquidations disabled");

        uint256 n = liquidationData.length;
        for (uint256 i; i < n;) {
            (uint256 newRepaid, uint256 newSeized) = _liquidate(liquidationData[i], oracleResult);
            unchecked {
                repaid += newRepaid;
                seized += newSeized;
                ++i;
            }
        }

        IERC20(collateral).transfer(msg.sender, seized);
        IBlueLiquidateCallback(msg.sender).blueLiquidateCallback(repaid, seized, data);
        IERC20(borrowing).transferFrom(msg.sender, address(this), repaid);
    }

    function _liquidate(LiquidationData calldata liquidationData, IBlueOracle.BlueOracleResult memory oracleResult)
        internal
        returns (uint256 repaid, uint256 seized)
    {
        bytes32 account = liquidationData.account;

        Tranche.Self memory tranche = tranches[account.lltv()].cache();
        _updateIndexes(tranche, account.lltv());

        Borrow storage accountBorrow = borrows[account];

        uint256 normalizedBorrow = accountBorrow.scaledBorrow.toNormalized(tranche.borrowIndex);
        uint256 ltv = computeLTV(accountBorrow.collateral, normalizedBorrow, oracleResult);

        require(ltv > account.lltv(), "not liquidatable");

        // todo

        tranches[account.lltv()].commit(tranche);
    }

    function _borrowInCollateral(uint256 borrowAmount, IBlueOracle.BlueOracleResult memory oracleResult)
        internal
        pure
        returns (uint256 borrowInCollateral)
    {
        // todo: use full math
        borrowInCollateral = (borrowAmount * oracleResult.priceMantissa).mulTenPowi(oracleResult.priceExponent);
    }

    function computeLTV(
        uint256 collateralAmount,
        uint256 borrowAmount,
        IBlueOracle.BlueOracleResult memory oracleResult
    ) public pure returns (uint256) {
        if (borrowAmount == 0) return 0;
        return _borrowInCollateral(borrowAmount, oracleResult).wadDiv(collateralAmount);
    }

    function _updateIndexes(Tranche.Self memory tranche, uint256 lltv) internal {
        uint256 elapsed = block.timestamp - tranche.lastUpdate;

        if (elapsed == 0) return;

        uint256 utilization = tranche.utilization();
        uint256 rate = irm.rate(lltv, utilization);
        uint256 indexIncrease = rate.wadMul(elapsed);
        tranche.borrowIndex += indexIncrease;
        tranche.supplyIndex += indexIncrease.wadMul(utilization);
    }
}
