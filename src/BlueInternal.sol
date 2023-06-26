// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Types} from "src/libraries/Types.sol";
import {IBlueOracle} from "src/interfaces/IBlueOracle.sol";
import {IBlueInterestModel} from "src/interfaces/IBlueInterestModel.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {BlueStorage} from "src/BlueStorage.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

abstract contract BlueInternal is BlueStorage {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using Math for uint256;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    modifier marketInitialized(Types.MarketParams calldata params) {
        require(_markets[_marketId(params)].initialized);
        _;
    }

    modifier trancheInitialized(Types.MarketParams calldata params, uint256 lltv) {
        require(_markets[_marketId(params)].tranches[lltv].liquidationBonus != 0);
        _;
    }

    function _initializeMarket(Types.MarketParams calldata params, address feeRecipient, uint96 positionId) internal {
        Types.Market storage market = _markets[_marketId(params)];
        require(!market.initialized);
        market.feeRecipient = _userIdKey(feeRecipient, positionId);
        market.initialized = true;
    }

    function _initializeTranche(Types.MarketParams calldata params, uint256 lltv, uint256 liquidationBonus) internal {
        Types.Tranche storage tranche = _markets[_marketId(params)].tranches[lltv];
        require(tranche.liquidationBonus == 0 && liquidationBonus != 0 && liquidationBonus <= (WadRayMath.RAY - lltv));
        tranche.liquidationBonus = liquidationBonus;
    }

    function _supplyCollateral(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address from,
        address onBehalf,
        uint96 positionId
    ) internal returns (uint256 supplied) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(onBehalf, positionId)];

        _transfer(params.collateralToken, from, address(this), amount);

        position.collateral += amount;

        supplied = amount;
    }

    function _withdrawCollateral(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        address receiver,
        uint96 positionId
    ) internal returns (uint256 withdrawn) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(onBehalf, positionId)];
        Types.OracleData memory oracleData = _oracleData(params);

        _accrue(params, lltv);

        position.collateral -= amount;

        _liquidityCheck(params, lltv, onBehalf, positionId, oracleData);
        _transfer(params.collateralToken, address(this), receiver, amount);
        withdrawn = amount;
    }

    function _supply(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address from,
        address onBehalf,
        uint96 positionId
    ) internal returns (uint256 supplied) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(onBehalf, positionId)];

        _transfer(params.debtToken, from, address(this), amount);
        _accrue(params, lltv);

        uint256 shares = _assetsToSharesUp(amount, tranche.supply);
        position.supplyShares += shares;
        tranche.supply.shares += shares;
        tranche.supply.amount += amount;

        supplied = amount;
    }

    function _withdraw(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        address receiver,
        uint96 positionId
    ) internal returns (uint256 withdrawn) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(onBehalf, positionId)];

        _accrue(params, lltv);
        require(tranche.supply.amount - amount >= tranche.debt.amount);

        uint256 shares = _assetsToSharesUp(amount, tranche.supply);
        position.supplyShares -= shares;
        tranche.supply.shares -= shares;
        tranche.supply.amount -= amount;

        _transfer(params.debtToken, address(this), receiver, amount);
        withdrawn = amount;
    }

    function _borrow(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address onBehalf,
        address receiver,
        uint96 positionId
    ) internal returns (uint256 borrowed) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(onBehalf, positionId)];

        Types.OracleData memory oracleData = _oracleData(params);
        require(!oracleData.borrowPaused);

        _accrue(params, lltv);
        require(tranche.supply.amount >= tranche.debt.amount + amount);

        uint256 shares = _assetsToSharesUp(amount, tranche.debt);
        position.debtShares += shares;
        tranche.debt.shares += shares;
        tranche.debt.amount += amount;

        _liquidityCheck(params, lltv, onBehalf, positionId, oracleData);
        _transfer(params.debtToken, address(this), receiver, amount);
        borrowed = amount;
    }

    function _repay(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address from,
        address onBehalf,
        uint96 positionId
    ) internal returns (uint256 repaid) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(onBehalf, positionId)];

        _accrue(params, lltv);

        _transfer(params.debtToken, from, address(this), amount);
        uint256 shares = _assetsToSharesDown(amount, tranche.debt);
        position.debtShares -= shares;
        tranche.debt.shares -= shares;
        tranche.debt.amount -= amount;

        repaid = amount;
    }

    function _liquidate(
        Types.MarketParams calldata params,
        uint256 lltv,
        uint256 amount,
        address liquidator,
        address liquidatee,
        uint96 positionId
    ) internal returns (uint256 liquidated) {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(liquidatee, positionId)];
        Types.OracleData memory oracleData = _oracleData(params);

        _accrue(params, lltv);

        require(!oracleData.liquidationPaused);
        require(!_liquidityCheck(params, lltv, liquidatee, positionId, oracleData));

        _transfer(params.debtToken, liquidator, address(this), amount);

        liquidated = amount.rayDiv(oracleData.price).rayMul(WadRayMath.RAY + tranche.liquidationBonus);

        position.collateral -= liquidated;

        _transfer(params.collateralToken, address(this), liquidator, liquidated);
    }

    function _accrue(Types.MarketParams calldata params, uint256 lltv) internal {
        Types.Market storage market = _markets[_marketId(params)];
        Types.Tranche storage tranche = market.tranches[lltv];
        uint256 timeElapsed = block.timestamp - tranche.lastUpdateTimestamp;
        if (timeElapsed == 0) return;

        (uint256 accrual) = IBlueInterestModel(params.interestRateModel).accrue(
            params, lltv, tranche.supply.amount, tranche.debt.amount, timeElapsed
        );
        tranche.supply.amount += accrual;
        tranche.debt.amount += accrual;
        uint256 fee = market.fee;
        if (fee > 0) {
            require(fee <= PercentageMath.PERCENTAGE_FACTOR);
            uint256 feeShares = _assetsToSharesDown(accrual.percentMulDown(fee), tranche.supply);
            tranche.positions[market.feeRecipient].supplyShares += feeShares;
            tranche.supply.shares += feeShares;
        }
    }

    function _transfer(address asset, address from, address to, uint256 amount) internal {
        ERC20(asset).safeTransferFrom(from, to, amount);
    }

    function _liquidityCheck(
        Types.MarketParams calldata params,
        uint256 lltv,
        address user,
        uint96 positionId,
        Types.OracleData memory oracleData
    ) internal view returns (bool) {
        Types.Tranche storage tranche = _markets[_marketId(params)].tranches[lltv];
        Types.Position storage position = tranche.positions[_userIdKey(user, positionId)];
        uint256 debt = _sharesToAssetsUp(position.debtShares, tranche.debt);

        return position.collateral.rayMul(oracleData.price).rayMul(lltv) >= debt;
    }

    function _oracleData(Types.MarketParams calldata params) internal view returns (Types.OracleData memory) {
        return IBlueOracle(params.oracle).getMarketData(params.collateralToken, params.debtToken);
    }

    function _assetsToSharesDown(uint256 assets, Types.Liquidity memory liquidity) internal view returns (uint256) {
        return assets.mulDivDown(liquidity.shares + 10 ** _decimalsOffset(), liquidity.amount);
    }

    function _assetsToSharesUp(uint256 assets, Types.Liquidity memory liquidity) internal view returns (uint256) {
        return assets.mulDivUp(liquidity.shares + 10 ** _decimalsOffset(), liquidity.amount);
    }

    function _sharesToAssetsDown(uint256 shares, Types.Liquidity memory liquidity) internal view returns (uint256) {
        return shares.mulDivDown(liquidity.amount + 1, liquidity.shares + 10 ** _decimalsOffset());
    }

    function _sharesToAssetsUp(uint256 shares, Types.Liquidity memory liquidity) internal view returns (uint256) {
        return shares.mulDivUp(liquidity.amount + 1, liquidity.shares + 10 ** _decimalsOffset());
    }

    function _decimalsOffset() internal view virtual returns (uint256) {
        return 0;
    }

    function _marketId(Types.MarketParams memory params) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(params.collateralToken, params.debtToken, params.oracle, params.interestRateModel, params.salt)
        );
    }

    function _userIdKey(address user, uint96 positionId) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(user)) << 96) + positionId);
    }
}
