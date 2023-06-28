// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Constants} from "src/libraries/Constants.sol";

import {Types} from "src/libraries/Types.sol";

import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {Math} from "@morpho-utils/math/Math.sol";

library BadDebtAccounting {
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using Math for uint256;

    /// @notice Computes the bad debt of a user and puts his position on the threshold of liquidation.
    /// @notice Reduces the supply index to take into account the bad debt for suppliers.
    function computeBadDebt(Types.Market storage market, address user) internal {
        (uint256 debt,) = HealthFactor.computeDebtAndAvgLltv(market, user, 0, 0);

        uint256 collateralBalance = market.collateralBalance[user];
        (,, uint256 borrowUnit, uint256 borrowPrice) = HealthFactor.assetData(market);

        uint256 collateralValue = computeCollateralValue(market, collateralBalance);

        if (collateralValue > debt * borrowPrice / borrowUnit) revert Errors.NoBadDebt();

        uint256[] memory borrowerLltvMap = EnumerableSet.values(market.borrowerLltvMapSet[user]);
        borrowerLltvMap = sort(borrowerLltvMap);

        uint256 i = 1;
        uint256 length = borrowerLltvMap.length;
        uint256 tranche;
        uint256 borrowBalance;
        while (i < length) {
            tranche = borrowerLltvMap[length - i];
            borrowBalance = market.borrowBalance[user][tranche].rayMul(market.tranches[tranche].borrowIndex);

            if (
                collateralValue.wadDivDown(WadRayMath.WAD + HealthFactor.getLiquidationBonus(tranche))
                    > (debt.zeroFloorSub(borrowBalance)) * borrowPrice / borrowUnit
            ) {
                i = length + 1;
                borrowBalance = debt
                    - (collateralValue.wadDivDown(WadRayMath.WAD + HealthFactor.getLiquidationBonus(tranche)) * borrowUnit)
                        / borrowPrice;
                updateMarketTranche(market, borrowBalance, tranche);
                market.borrowBalance[user][tranche] -= borrowBalance.rayDiv(market.tranches[tranche].borrowIndex);
            } else {
                debt -= borrowBalance;
                updateMarketTranche(market, borrowBalance, tranche);
                market.borrowBalance[user][tranche] = 0;
                ++i;
            }
        }
    }

    function computeCollateralValue(Types.Market storage market, uint256 collateralBalance)
        internal
        view
        returns (uint256 collateralValue)
    {
        (uint256 collateralUnit, uint256 collateralPrice,,) = HealthFactor.assetData(market);

        collateralValue = (collateralBalance * collateralPrice) / collateralUnit;
    }

    function updateMarketTranche(Types.Market storage market, uint256 differenceBalance, uint256 i) internal {
        market.tranches[i].supplyIndex -=
            differenceBalance.rayDiv(market.tranches[i].totalSupply.rayMul(market.tranches[i].supplyIndex));
        market.tranches[i].totalBorrow -= differenceBalance.rayDiv(market.tranches[i].borrowIndex);
    }

    function sort(uint256[] memory data) internal pure returns (uint256[] memory) {
        quickSort(data, uint256(0), uint256(data.length - 1));
        return data;
    }

    function quickSort(uint256[] memory arr, uint256 left, uint256 right) internal pure {
        uint256 i = left;
        uint256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) {
            quickSort(arr, left, j);
        }
        if (i < right) {
            quickSort(arr, i, right);
        }
    }
}
