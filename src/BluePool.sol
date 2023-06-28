// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {BlueStorage} from "src/BlueStorage.sol";
import {BadDebtAccounting} from "src/libraries/BadDebtAccounting.sol";
import {Constants} from "src/libraries/Constants.sol";

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {InterestRatesManager} from "src/libraries/InterestRatesManager.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";

import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Math} from "@morpho-utils/math/Math.sol";

contract BluePool is BlueStorage {
    using WadRayMath for uint256;
    using Math for uint256;
    using InterestRatesManager for Types.Market;
    using HealthFactor for Types.Market;
    using BadDebtAccounting for Types.Market;

    using SafeTransferLib for ERC20;

    function createPool(address collateralToken, address poolToken, uint16 reserveFactor, IOracle oracle, address pool)
        external
    {
        Types.Market storage market = _marketMap[pool];

        market.collateral = collateralToken;
        market.token = poolToken;
        market.oracle = oracle;
        market.reserveFactor = reserveFactor;

        for (uint256 i; i < Constants.TRANCHE_NUMBER; ++i) {
            market.tranches.push(
                Types.Tranche({
                    totalSupply: 0,
                    totalBorrow: 0,
                    supplyIndex: WadRayMath.RAY,
                    borrowIndex: WadRayMath.RAY,
                    lastUpdateTimestamp: block.timestamp
                })
            );
        }
    }

    function supply(address pool, uint256 amount, uint256 trancheNumber) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();
        if (trancheNumber > Constants.TRANCHE_NUMBER) revert Errors.TrancheNotCreated();

        market.updateIndexes(trancheNumber);
        EnumerableSet.add(market.supplierLltvMapSet[msg.sender], trancheNumber);

        ERC20(market.token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 supplyAmount = amount.rayDivUp(market.tranches[trancheNumber].supplyIndex);

        market.supplyBalance[msg.sender][trancheNumber] += supplyAmount;

        market.tranches[trancheNumber].totalSupply += supplyAmount;
        emit Events.Supplied(msg.sender, msg.sender, pool, amount, trancheNumber);
    }

    function withdraw(address pool, address receiver, uint256 amount, uint256 trancheNumber) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();

        market.updateIndexes(trancheNumber);

        uint256 withdrawAmount = amount.rayDivUp(market.tranches[trancheNumber].supplyIndex);
        withdrawAmount = Math.min(withdrawAmount, market.supplyBalance[msg.sender][trancheNumber]);

        if (
            (
                (market.tranches[trancheNumber].totalSupply - withdrawAmount).rayMul(
                    market.tranches[trancheNumber].supplyIndex
                )
            ) < market.tranches[trancheNumber].totalBorrow.rayMul(market.tranches[trancheNumber].borrowIndex)
        ) revert Errors.NotEnoughLiquidityToWithdraw();

        market.supplyBalance[msg.sender][trancheNumber] -= withdrawAmount;
        market.tranches[trancheNumber].totalSupply -= withdrawAmount;
        if (market.supplyBalance[msg.sender][trancheNumber] == 0) {
            EnumerableSet.remove(market.supplierLltvMapSet[msg.sender], trancheNumber);
        }

        ERC20(market.token).safeTransfer(
            receiver, withdrawAmount.rayMulDown(market.tranches[trancheNumber].supplyIndex)
        );
        emit Events.Withdrawn(msg.sender, msg.sender, receiver, pool, amount, trancheNumber);
    }

    function supplyCollateral(address pool, uint256 amount, uint256 trancheNumber) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();
        if (trancheNumber > Constants.TRANCHE_NUMBER) revert Errors.TrancheNotCreated();

        ERC20(market.collateral).safeTransferFrom(msg.sender, address(this), amount);

        market.collateralBalance[msg.sender] += amount;
        emit Events.CollateralSupplied(msg.sender, msg.sender, pool, amount, trancheNumber);
    }

    function withdrawCollateral(address pool, address receiver, uint256 amount) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();

        uint256 length = EnumerableSet.length(market.borrowerLltvMapSet[msg.sender]);
        for (uint256 i; i < length; ++i) {
            uint256 tranche = EnumerableSet.at(market.borrowerLltvMapSet[msg.sender], i);
            market.updateIndexes(tranche);
        }

        uint256 withdrawAmount = Math.min(amount, market.collateralBalance[msg.sender]);

        if (market.getHealthFactor(msg.sender, withdrawAmount, 0, 0) < WadRayMath.WAD) {
            revert Errors.HealthFactorTooLow();
        }

        market.collateralBalance[msg.sender] -= withdrawAmount;

        ERC20(market.token).safeTransfer(receiver, withdrawAmount);
        emit Events.CollateralWithdrawn(msg.sender, msg.sender, receiver, pool, amount);
    }

    function borrow(address pool, address receiver, uint256 amount, uint256 trancheNumber) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();
        if (trancheNumber > Constants.TRANCHE_NUMBER) revert Errors.TrancheNotCreated();

        uint256 length = EnumerableSet.length(market.borrowerLltvMapSet[msg.sender]);
        for (uint256 i; i < length; ++i) {
            uint256 tranche = EnumerableSet.at(market.borrowerLltvMapSet[msg.sender], i);
            market.updateIndexes(tranche);
        }

        EnumerableSet.add(market.borrowerLltvMapSet[msg.sender], trancheNumber);
        uint256 borrowAmount = amount.rayDivUp(market.tranches[trancheNumber].borrowIndex);

        if (
            ((market.tranches[trancheNumber].totalSupply).rayMul(market.tranches[trancheNumber].supplyIndex))
                < market.tranches[trancheNumber].totalBorrow.rayMul(market.tranches[trancheNumber].borrowIndex) + amount
        ) {
            revert Errors.NotEnoughLiquidityToBorrow();
        }

        if (market.getHealthFactor(msg.sender, 0, borrowAmount, trancheNumber) < WadRayMath.WAD) {
            revert Errors.HealthFactorTooLow();
        }

        market.borrowBalance[msg.sender][trancheNumber] += borrowAmount;
        market.tranches[trancheNumber].totalBorrow += borrowAmount;

        ERC20(market.token).safeTransfer(receiver, amount);

        emit Events.Borrowed(msg.sender, msg.sender, receiver, pool, amount, trancheNumber);
    }

    function repay(address pool, uint256 amount, uint256 trancheNumber) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();
        if (trancheNumber > Constants.TRANCHE_NUMBER) revert Errors.TrancheNotCreated();

        market.updateIndexes(trancheNumber);

        ERC20(market.token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 repaidAmount = amount.rayDivUp(market.tranches[trancheNumber].borrowIndex);

        market.borrowBalance[msg.sender][trancheNumber] -= repaidAmount;
        market.tranches[trancheNumber].totalBorrow -= repaidAmount;
        if (market.borrowBalance[msg.sender][trancheNumber] == 0) {
            EnumerableSet.remove(market.supplierLltvMapSet[msg.sender], trancheNumber);
        }
        emit Events.Repaid(msg.sender, msg.sender, pool, amount, trancheNumber);
    }

    function liquidate(address pool, address user, uint256 amount, uint256 trancheNumber) external {
        Types.Market storage market = _marketMap[pool];

        if (market.token == address(0)) revert Errors.MarketNotCreated();

        uint256 length = EnumerableSet.length(market.borrowerLltvMapSet[msg.sender]);
        for (uint256 i; i < length; ++i) {
            uint256 tranche = EnumerableSet.at(market.borrowerLltvMapSet[msg.sender], i);
            market.updateIndexes(tranche);
        }

        if (market.getHealthFactor(user, 0, 0, 0) < WadRayMath.WAD) revert Errors.LiquidationNotAuthorized();

        uint256 seized;
        (amount, seized) = market.calculateAmountToSeize(amount, user, trancheNumber);

        if (amount == 0) revert Errors.AmountIsZero();

        market.borrowBalance[user][trancheNumber] -= amount.rayDivDown(market.tranches[trancheNumber].borrowIndex);
        market.tranches[trancheNumber].totalBorrow -= amount.rayDivDown(market.tranches[trancheNumber].borrowIndex);
        market.collateralBalance[user] -= seized;

        ERC20(market.token).safeTransferFrom(msg.sender, address(this), amount);

        ERC20(market.collateral).safeTransfer(msg.sender, seized);

        emit Events.Liquidated(msg.sender, user, pool, market.token, amount, market.collateral, seized);
    }

    function realizeBadDebt(address pool, address user) external {
        Types.Market storage market = _marketMap[pool];
        if (market.token == address(0)) revert Errors.MarketNotCreated();

        uint256 length = EnumerableSet.length(market.borrowerLltvMapSet[msg.sender]);
        for (uint256 i; i < length; ++i) {
            uint256 tranche = EnumerableSet.at(market.borrowerLltvMapSet[msg.sender], i);
            market.updateIndexes(tranche);
        }

        market.computeBadDebt(user);
    }
}
