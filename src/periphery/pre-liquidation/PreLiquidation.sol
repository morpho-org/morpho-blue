// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Id, MarketParams, IMorpho, Position, Market} from "../../interfaces/IMorpho.sol";
import {IMorphoRepayCallback} from "../../interfaces/IMorphoCallbacks.sol";
import {IPreLiquidation, PreLiquidationParams} from "./interfaces/IPreLiquidation.sol";
import {IPreLiquidationCallback} from "./interfaces/IPreLiquidationCallback.sol";
import {IOracle} from "../../interfaces/IOracle.sol";

import {ORACLE_PRICE_SCALE} from "../../libraries/ConstantsLib.sol";
import {SharesMathLib} from "../../libraries/SharesMathLib.sol";
import {SafeTransferLib} from "../../../lib/solmate/src/utils/SafeTransferLib.sol";
import {WAD, MathLib} from "../../libraries/MathLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

/// @title PreLiquidation
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice A linear LIF and linear LCF pre-liquidation contract for Morpho.
contract PreLiquidation is IPreLiquidation, IMorphoRepayCallback {
    using SharesMathLib for uint256;
    using MathLib for uint256;
    using SafeTransferLib for ERC20;

    /* IMMUTABLE */

    /// @notice The address of the Morpho contract.
    IMorpho public immutable MORPHO;
    /// @notice The id of the Morpho Market specific to the PreLiquidation contract.
    Id public immutable ID;

    // Market parameters
    address internal immutable LOAN_TOKEN;
    address internal immutable COLLATERAL_TOKEN;
    address internal immutable ORACLE;
    address internal immutable IRM;
    uint256 internal immutable LLTV;

    // Pre-liquidation parameters
    uint256 internal immutable PRE_LLTV;
    uint256 internal immutable PRE_LCF_1;
    uint256 internal immutable PRE_LCF_2;
    uint256 internal immutable PRE_LIF_1;
    uint256 internal immutable PRE_LIF_2;
    address internal immutable PRE_LIQUIDATION_ORACLE;

    /// @notice The Morpho market parameters specific to the PreLiquidation contract.
    function marketParams() public view returns (MarketParams memory) {
        return
            MarketParams({
                loanToken: LOAN_TOKEN, collateralToken: COLLATERAL_TOKEN, oracle: ORACLE, irm: IRM, lltv: LLTV
            });
    }

    /// @notice The pre-liquidation parameters specific to the PreLiquidation contract.
    function preLiquidationParams() external view returns (PreLiquidationParams memory) {
        return PreLiquidationParams({
            preLltv: PRE_LLTV,
            preLCF1: PRE_LCF_1,
            preLCF2: PRE_LCF_2,
            preLIF1: PRE_LIF_1,
            preLIF2: PRE_LIF_2,
            preLiquidationOracle: PRE_LIQUIDATION_ORACLE
        });
    }

    /* CONSTRUCTOR */

    /// @dev Initializes the PreLiquidation contract.
    /// @param morpho The address of the Morpho contract.
    /// @param id The id of the Morpho market on which pre-liquidations will occur.
    /// @param _preLiquidationParams The pre-liquidation parameters.
    /// @dev The following requirements should be met:
    /// - preLltv < LLTV;
    /// - preLCF1 <= preLCF2;
    /// - preLCF1 <= 1;
    /// - 1 <= preLIF1 <= preLIF2 <= 1 / LLTV.
    constructor(address morpho, Id id, PreLiquidationParams memory _preLiquidationParams) {
        require(IMorpho(morpho).market(id).lastUpdate != 0, ErrorsLib.NonexistentMarket());
        MarketParams memory _marketParams = IMorpho(morpho).idToMarketParams(id);
        require(_preLiquidationParams.preLltv < _marketParams.lltv, ErrorsLib.PreLltvTooHigh());
        require(_preLiquidationParams.preLCF1 <= _preLiquidationParams.preLCF2, ErrorsLib.PreLCFDecreasing());
        require(_preLiquidationParams.preLCF1 <= WAD, ErrorsLib.PreLCFTooHigh());
        require(WAD <= _preLiquidationParams.preLIF1, ErrorsLib.PreLIFTooLow());
        require(_preLiquidationParams.preLIF1 <= _preLiquidationParams.preLIF2, ErrorsLib.PreLIFDecreasing());
        require(_preLiquidationParams.preLIF2 <= WAD.wDivDown(_marketParams.lltv), ErrorsLib.PreLIFTooHigh());

        MORPHO = IMorpho(morpho);

        ID = id;

        LOAN_TOKEN = _marketParams.loanToken;
        COLLATERAL_TOKEN = _marketParams.collateralToken;
        ORACLE = _marketParams.oracle;
        IRM = _marketParams.irm;
        LLTV = _marketParams.lltv;

        PRE_LLTV = _preLiquidationParams.preLltv;
        PRE_LCF_1 = _preLiquidationParams.preLCF1;
        PRE_LCF_2 = _preLiquidationParams.preLCF2;
        PRE_LIF_1 = _preLiquidationParams.preLIF1;
        PRE_LIF_2 = _preLiquidationParams.preLIF2;
        PRE_LIQUIDATION_ORACLE = _preLiquidationParams.preLiquidationOracle;

        ERC20(_marketParams.loanToken).safeApprove(morpho, type(uint256).max);
    }

    /* PRE-LIQUIDATION */

    /// @notice Pre-liquidates the given borrower on the market of this contract and with the parameters of this
    /// contract.
    /// @param borrower The owner of the position.
    /// @param seizedAssets The amount of collateral to seize.
    /// @param repaidShares The amount of shares to repay.
    /// @param data Arbitrary data to pass to the `onPreLiquidate` callback. Pass empty data if not needed.
    /// @return seizedAssets The amount of collateral seized.
    /// @return repaidAssets The amount of debt repaid.
    /// @dev Either `seizedAssets` or `repaidShares` should be zero.
    /// @dev Reverts if the account is still liquidatable on Morpho after the pre-liquidation (withdrawCollateral will
    /// fail). This can happen if either the LIF is bigger than 1/LLTV, or if the account is already unhealthy on
    /// Morpho.
    /// @dev The pre-liquidation close factor (preLCF) is the maximum proportion of debt that can be pre-liquidated at
    /// once. It increases linearly from preLCF1 at preLltv to preLCF2 at LLTV.
    /// @dev The pre-liquidation incentive factor (preLIF) is the factor by which the repaid debt is multiplied to
    /// compute the seized collateral. It increases linearly from preLIF1 at preLltv to preLIF2 at LLTV.
    function preLiquidate(address borrower, uint256 seizedAssets, uint256 repaidShares, bytes calldata data)
        external
        returns (uint256, uint256)
    {
        require(UtilsLib.exactlyOneZero(seizedAssets, repaidShares), ErrorsLib.InconsistentInput());

        MORPHO.accrueInterest(marketParams());

        Market memory market = MORPHO.market(ID);
        Position memory position = MORPHO.position(ID, borrower);

        uint256 collateralPrice = IOracle(PRE_LIQUIDATION_ORACLE).price();
        uint256 collateralQuoted = uint256(position.collateral).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        uint256 borrowed = uint256(position.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);

        // The two following require-statements ensure that collateralQuoted is different from zero.
        require(borrowed <= collateralQuoted.wMulDown(LLTV), ErrorsLib.LiquidatablePosition());
        // The following require-statement is equivalent to checking that ltv > PRE_LLTV.
        require(borrowed > collateralQuoted.wMulDown(PRE_LLTV), ErrorsLib.NotPreLiquidatablePosition());

        uint256 ltv = borrowed.wDivUp(collateralQuoted);
        uint256 quotient = (ltv - PRE_LLTV).wDivDown(LLTV - PRE_LLTV);
        uint256 preLIF = quotient.wMulDown(PRE_LIF_2 - PRE_LIF_1) + PRE_LIF_1;

        if (seizedAssets > 0) {
            uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);

            repaidShares =
                seizedAssetsQuoted.wDivUp(preLIF).toSharesUp(market.totalBorrowAssets, market.totalBorrowShares);
        } else {
            seizedAssets = repaidShares.toAssetsDown(market.totalBorrowAssets, market.totalBorrowShares)
                .wMulDown(preLIF)
                .mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
        }

        // Note that the pre-liquidation close factor can be greater than WAD (100%).
        // In this case the position can be fully pre-liquidated.
        uint256 preLCF = quotient.wMulDown(PRE_LCF_2 - PRE_LCF_1) + PRE_LCF_1;

        uint256 repayableShares = uint256(position.borrowShares).wMulDown(preLCF);
        require(repaidShares <= repayableShares, ErrorsLib.PreLiquidationTooLarge(repaidShares, repayableShares));

        bytes memory callbackData = abi.encode(seizedAssets, borrower, msg.sender, data);
        (uint256 repaidAssets,) = MORPHO.repay(marketParams(), 0, repaidShares, borrower, callbackData);

        emit EventsLib.PreLiquidate(ID, msg.sender, borrower, repaidAssets, repaidShares, seizedAssets);

        return (seizedAssets, repaidAssets);
    }

    /// @notice Morpho callback after repay call.
    /// @dev During pre-liquidation, Morpho will call the `onMorphoRepay` callback function in `PreLiquidation` using
    /// the provided `data`.
    function onMorphoRepay(uint256 repaidAssets, bytes calldata callbackData) external {
        require(msg.sender == address(MORPHO), ErrorsLib.NotMorpho());
        (uint256 seizedAssets, address borrower, address liquidator, bytes memory data) =
            abi.decode(callbackData, (uint256, address, address, bytes));

        MORPHO.withdrawCollateral(marketParams(), seizedAssets, borrower, liquidator);

        if (data.length > 0) {
            IPreLiquidationCallback(liquidator).onPreLiquidate(repaidAssets, data);
        }

        ERC20(LOAN_TOKEN).safeTransferFrom(liquidator, address(this), repaidAssets);
    }
}
