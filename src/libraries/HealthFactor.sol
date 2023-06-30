// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Constants} from "./Constants.sol";
import {Types} from "./Types.sol";
import {Errors} from "./Errors.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

library HealthFactor {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice check if the health factor of a user is above the minimal threshold if it was in a given tranche.
    function getHealthFactor(
        Types.Market storage market,
        address user,
        uint256 amountWithdraw,
        uint256 amountBorrow,
        uint256 trancheNumber
    ) internal view returns (uint256) {
        (uint256 avgLltv, uint256 debt) = computeDebtAndAvgLltv(market, user, amountBorrow, trancheNumber);
        uint256 collateral = (amountWithdraw + market.collateralBalance[user]);
        (uint256 collateralUnit, uint256 collateralPrice, uint256 borrowUnit, uint256 borrowPrice) = assetData(market);

        collateral = collateral * collateralPrice / collateralUnit;
        collateral = collateral.percentMulDown(avgLltv);
        debt = debt * borrowPrice / borrowUnit;
        return collateral.wadDivDown(debt);
    }

    function computeDebtAndAvgLltv(
        Types.Market storage market,
        address user,
        uint256 amountBorrow,
        uint256 trancheNumber
    ) internal view returns (uint256 avgLltv, uint256 debt) {
        EnumerableSet.UintSet storage borrowerLltvMapSet = market.borrowerLltvMapSet[user];
        uint256 borrowBalance;
        uint256 length = EnumerableSet.length(borrowerLltvMapSet);
        uint256 scaledBorrowBalance;
        uint256 lltv;
        for (uint256 i; i < length; ++i) {
            uint256 tranche = borrowerLltvMapSet.at(i);
            lltv = getLiquidationLtv(tranche);
            scaledBorrowBalance = market.borrowBalance[user][tranche];
            borrowBalance = scaledBorrowBalance.rayMulUp(market.tranches[tranche].borrowIndex);
            if (tranche == trancheNumber) {
                borrowBalance += amountBorrow;
            }

            debt += borrowBalance;
            avgLltv += lltv * borrowBalance;
        }
        avgLltv = avgLltv / debt;
    }

    /// @notice Get the liquidation Loan To Value for a given tranche.
    function getLiquidationLtv(uint256 trancheNumber) internal pure returns (uint256) {
        return ((trancheNumber + 1) * PercentageMath.PERCENTAGE_FACTOR) / Constants.TRANCHE_NUMBER;
    }

    /// @notice Get the liquidation bonus for a given tranche.
    function getLiquidationBonus(uint256 trancheNumber) internal pure returns (uint256) {
        return Constants.ALPHA.wadMul(WadRayMath.WAD.wadDiv(getLiquidationLtv(trancheNumber)) - WadRayMath.WAD);
    }

    function assetData(Types.Market storage market)
        internal
        view
        returns (uint256 collateralUnit, uint256 collateralPrice, uint256 borrowUnit, uint256 borrowPrice)
    {
        collateralPrice = market.oracle.collateralPrice();

        borrowPrice = market.oracle.borrowPrice();

        collateralUnit = 10 ** (ERC20(market.collateral).decimals());

        borrowUnit = 10 ** (ERC20(market.token).decimals());
    }

    function calculateAmountToSeize(Types.Market storage market, uint256 amount, address user, uint256 trancheNumber)
        internal
        view
        returns (uint256, uint256)
    {
        amount = Math.min(
            amount, market.borrowBalance[user][trancheNumber].rayMul(market.tranches[trancheNumber].borrowIndex)
        );

        uint256 liquidationBonus = getLiquidationBonus(trancheNumber);
        (uint256 collateralUnit, uint256 collateralPrice, uint256 borrowUnit, uint256 borrowPrice) = assetData(market);

        uint256 seized = amount * (borrowPrice * collateralUnit) / (borrowUnit * collateralPrice);
        seized += seized.wadMul(liquidationBonus);

        if (seized > market.collateralBalance[user]) {
            seized = market.collateralBalance[user];
            amount = seized * collateralPrice * borrowUnit
                / (borrowPrice * collateralUnit).wadDivUp(WadRayMath.WAD + liquidationBonus);
        }

        return (amount, seized);
    }
}
