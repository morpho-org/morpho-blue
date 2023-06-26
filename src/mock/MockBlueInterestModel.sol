// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IBlueInterestModel} from "src/interfaces/IBlueInterestModel.sol";
import {Types} from "src/libraries/Types.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

contract MockBlueInterestModel is IBlueInterestModel {
    using WadRayMath for uint256;

    /// @dev All in RAY.
    uint256 internal immutable _targetUtilization;
    uint256 internal immutable _baseRate; // base interest rate charged on all borrows
    uint256 internal immutable _slope1; // interest rate rate of increase up to target utilization
    uint256 internal immutable _slope2; // interest rate rate of increase above target utilization
    uint256 internal constant YEAR = 365 days;

    constructor(uint256 targetUtilization, uint256 baseRate, uint256 slope1, uint256 slope2) {
        _targetUtilization = targetUtilization;
        _baseRate = baseRate;
        _slope1 = slope1;
        _slope2 = slope2;
    }

    function accrue(
        Types.MarketParams calldata,
        uint256 lltv,
        uint256 totalSupply,
        uint256 totalDebt,
        uint256 timeElapsed
    ) external view returns (uint256 accrual) {
        uint256 utilization = totalDebt.rayDiv(totalSupply);
        uint256 aboveUtilization = utilization > _targetUtilization ? utilization - _targetUtilization : 0;

        uint256 interestRate = _baseRate + utilization.rayMul(_slope1) + aboveUtilization.rayMul(_slope2);
        // Just a simple model for now. This does not compound in a consistent way.
        accrual = totalDebt.rayMul(interestRate).rayMul(lltv) * timeElapsed / YEAR;
    }
}
