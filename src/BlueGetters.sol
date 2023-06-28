// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {BluePool} from "src/BluePool.sol";
import {Types} from "src/libraries/Types.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

abstract contract BlueGetters is BluePool {
    using WadRayMath for uint256;

    function getHealthFactor(address pool, address user) external view returns (uint256) {
        return HealthFactor.getHealthFactor(_marketMap[pool], user, 0, 0, 0);
    }

    function debtLiquidity(address pool, uint256 trancheNumber) external view returns (uint256) {
        return _marketMap[pool].tranches[trancheNumber].totalSupply.rayMul(
            _marketMap[pool].tranches[trancheNumber].supplyIndex
        )
            - _marketMap[pool].tranches[trancheNumber].totalBorrow.rayMul(
                _marketMap[pool].tranches[trancheNumber].borrowIndex
            );
    }

    function liquidationBonus(uint256 trancheNumber) external pure returns (uint256) {
        return HealthFactor.getLiquidationBonus(trancheNumber);
    }

    function lastUpdateTimestamp(address pool, uint256 trancheNumber) external view returns (uint256) {
        return _marketMap[pool].tranches[trancheNumber].lastUpdateTimestamp;
    }

    function trancheIndexes(address pool, uint256 trancheNumber) external view returns (uint256, uint256) {
        return
            (_marketMap[pool].tranches[trancheNumber].supplyIndex, _marketMap[pool].tranches[trancheNumber].borrowIndex);
    }

    function borrowPosition(address pool, address user, uint256 trancheNumber) external view returns (uint256) {
        return _marketMap[pool].borrowBalance[user][trancheNumber];
    }

    function supplyPosition(address pool, address user, uint256 trancheNumber) external view returns (uint256) {
        return _marketMap[pool].supplyBalance[user][trancheNumber];
    }

    function collateralPosition(address pool, address user) external view returns (uint256) {
        return _marketMap[pool].collateralBalance[user];
    }
}
