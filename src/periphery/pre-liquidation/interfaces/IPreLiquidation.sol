// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {Id, IMorpho, MarketParams} from "../../../interfaces/IMorpho.sol";

/// @notice The pre-liquidation parameters are:
///  - preLltv, the maximum LTV of a position before allowing pre-liquidation, scaled by WAD.
///  - preLCF1, the pre-liquidation close factor when the position LTV is equal to preLltv, scaled by WAD.
///  - preLCF2, the pre-liquidation close factor when the position LTV is equal to LLTV, scaled by WAD.
///  - preLIF1, the pre-liquidation incentive factor when the position LTV is equal to preLltv, scaled by WAD.
///  - preLIF2, the pre-liquidation incentive factor when the position LTV is equal to LLTV, scaled by WAD.
///  - preLiquidationOracle, the oracle used to assess whether or not a position can be preliquidated.
struct PreLiquidationParams {
    uint256 preLltv;
    uint256 preLCF1;
    uint256 preLCF2;
    uint256 preLIF1;
    uint256 preLIF2;
    address preLiquidationOracle;
}

interface IPreLiquidation {
    function MORPHO() external view returns (IMorpho);

    function ID() external view returns (Id);

    function marketParams() external returns (MarketParams memory);

    function preLiquidationParams() external view returns (PreLiquidationParams memory);

    function preLiquidate(address borrower, uint256 seizedAssets, uint256 repaidShares, bytes calldata data)
        external
        returns (uint256, uint256);
}
