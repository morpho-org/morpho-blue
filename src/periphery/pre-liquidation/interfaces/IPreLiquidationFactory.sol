// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {Id, IMorpho} from "../../../interfaces/IMorpho.sol";
import {IPreLiquidation, PreLiquidationParams} from "./IPreLiquidation.sol";

interface IPreLiquidationFactory {
    function MORPHO() external view returns (IMorpho);

    function isPreLiquidation(address) external returns (bool);

    function createPreLiquidation(Id id, PreLiquidationParams calldata preLiquidationParams)
        external
        returns (IPreLiquidation preLiquidation);
}
